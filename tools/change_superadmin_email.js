#!/usr/bin/env node
/**
 * Cambia el correo del Superadmin existente (UID, contraseña, rol, `activo` y
 * permisos no se tocan) en Authentication y en usuarios/{uid}.
 *
 * - El correo nuevo se pide por consola (dos veces); no queda en el historial.
 * - Por defecto es SIMULACIÓN: valida y muestra el plan, sin escribir.
 * - --apply escribe. El correo queda SIN verificar (emailVerified: false) hasta
 *   que el dueño del buzón abra el enlace real que envía la app.
 * - Orden: 1) Authentication, 2) Firestore (perfil + auditoría + índice de
 *   correos, en un lote atómico). Si el paso 2 falla, se revierte el paso 1.
 *   Si ni siquiera eso es posible, volver a ejecutar con el mismo correo
 *   reanuda solo lo pendiente (el plan es idempotente).
 * - No crea ni borra cuentas.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node change_superadmin_email.js            # simulación
 *   node change_superadmin_email.js --apply    # aplica (--uid <uid> si hay varios)
 */
const fs = require('node:fs');
const readline = require('node:readline/promises');
const admin = require('firebase-admin');
const { normalizeEmail, validateNewEmail, planEmailChange } = require('./lib/email_change');

const EXPECTED_PROJECT = 'la-granja-azul-app';

function fail(message) {
  console.error(message);
  process.exit(1);
}
const flag = (name) => process.argv.includes(`--${name}`);
const mask = (e) => e.replace(/^(.{2}).*(@.*)$/, '$1•••$2');

function initFirebase() {
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath) fail('Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la clave (fuera del repo).');
  let projectId;
  try {
    projectId = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
  } catch {
    fail('No se pudo leer la clave de servicio.');
  }
  if (projectId !== EXPECTED_PROJECT) fail(`La clave apunta a "${projectId}", se esperaba "${EXPECTED_PROJECT}".`);
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
  return projectId;
}

async function askNewEmail() {
  if (!process.stdin.isTTY) fail('Ejecuta el script en una terminal interactiva (el correo se pide por consola).');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const first = normalizeEmail(await rl.question('Correo nuevo del Superadmin: '));
    const second = normalizeEmail(await rl.question('Repite el correo: '));
    if (first !== second) fail('Los correos no coinciden.');
    return first;
  } finally {
    rl.close();
  }
}

async function findSuperadmin(db) {
  const wanted = process.argv[process.argv.indexOf('--uid') + 1];
  const snap = await db.collection('usuarios').where('rol', '==', 'superadmin').get();
  const matches = snap.docs.filter((d) => !flag('uid') || d.id === wanted);
  if (matches.length !== 1) fail(`Se esperaba exactamente 1 superadmin y hay ${matches.length}. Usa --uid <uid>.`);
  return matches[0];
}

/** Falla si el correo ya pertenece a otra cuenta (Auth, perfil o índice). */
async function assertEmailFree(db, uid, newEmail) {
  const conflicts = [];
  try {
    const other = await admin.auth().getUserByEmail(newEmail);
    if (other.uid !== uid) conflicts.push('ya existe otra cuenta en Authentication con ese correo');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  const profiles = await db.collection('usuarios').where('email', '==', newEmail).get();
  if (profiles.docs.some((d) => d.id !== uid)) conflicts.push('otro perfil de usuarios ya usa ese correo');
  const index = await db.collection('correos').doc(newEmail).get();
  if (index.exists && index.data().uid !== uid) conflicts.push('el índice de correos lo asigna a otro usuario');
  if (conflicts.length) fail('No se puede usar ese correo: ' + conflicts.join('; ') + '.');
}

async function updateAuth(uid, email, emailVerified) {
  await admin.auth().updateUser(uid, { email, emailVerified });
}

async function updateFirestore(db, ref, oldEmail, newEmail) {
  const audit = db.collection('auditoria').doc();
  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  batch.set(audit, {
    accion: 'cambiar_correo_superadmin',
    actorUid: 'admin-sdk',
    actorNombre: 'Herramienta administrativa',
    objetivo: ref.id,
    campos: ['email'],
    correoAnterior: mask(oldEmail),
    correoNuevo: mask(newEmail),
    creadoEn: now,
  });
  batch.set(ref, { email: newEmail, actualizadoEn: now, ultimaAuditoriaId: audit.id }, { merge: true });
  const oldIndex = db.collection('correos').doc(oldEmail);
  const oldSnap = await oldIndex.get();
  if (oldSnap.exists && oldSnap.data().uid === ref.id) batch.delete(oldIndex);
  batch.set(db.collection('correos').doc(newEmail), { uid: ref.id, creadoEn: now });
  await batch.commit();
}

async function main() {
  const projectId = initFirebase();
  const db = admin.firestore();
  const doc = await findSuperadmin(db);
  const uid = doc.id;
  const profile = doc.data();
  const auth = await admin.auth().getUser(uid);
  if (!auth.email) fail('La cuenta de Authentication no tiene correo.');

  console.log('Proyecto:', projectId);
  console.log('UID:', uid, '| rol:', profile.rol, '| activo:', profile.activo);
  console.log('Correo actual -> Auth:', mask(auth.email), '| Firestore:', mask(String(profile.email || '')),
    '| emailVerified:', auth.emailVerified);

  const newEmail = await askNewEmail();
  // Igual al actual no es error aquí: puede ser la reanudación de un cambio interrumpido.
  const errors = validateNewEmail(newEmail, '');
  if (errors.length) fail(errors.join('\n'));
  await assertEmailFree(db, uid, newEmail);

  const plan = planEmailChange({
    authEmail: normalizeEmail(auth.email),
    profileEmail: normalizeEmail(profile.email),
    newEmail,
  });
  if (plan.error) fail(plan.error);
  if (plan.steps.length === 0) {
    console.log('\nNada que hacer: Authentication y Firestore ya tienen ese correo.');
    return;
  }

  console.log('\nPlan (UID, contraseña, rol, activo y permisos NO se tocan):');
  console.log(' ·', mask(auth.email), '->', mask(newEmail), '| pasos:', plan.steps.join(' + '));
  console.log(' · emailVerified quedará en false hasta que se confirme el buzón real.');
  if (!flag('apply')) {
    console.log('\nSimulación: no se escribió nada. Repite con --apply para aplicar.');
    return;
  }

  const previous = { email: auth.email, emailVerified: auth.emailVerified };
  const authChanged = plan.steps.includes('auth');
  if (authChanged) {
    await updateAuth(uid, newEmail, false);
    console.log('✔ Authentication actualizado.');
  }
  if (plan.steps.includes('firestore')) {
    try {
      await updateFirestore(db, doc.ref, normalizeEmail(profile.email), newEmail);
      console.log('✔ Firestore actualizado.');
    } catch (e) {
      console.error('✘ Falló Firestore:', e.message);
      if (authChanged) {
        try {
          await updateAuth(uid, previous.email, previous.emailVerified);
          console.error('↩ Authentication revertido al correo anterior; no quedó nada a medias.');
        } catch (re) {
          console.error('⚠ No se pudo revertir Authentication:', re.message);
          console.error('  Authentication ya tiene el correo nuevo. Vuelve a ejecutar el script con el MISMO correo:');
          console.error('  reanuda solo el paso de Firestore.');
        }
      }
      process.exit(1);
    }
  }

  const [a, p] = [await admin.auth().getUser(uid), (await doc.ref.get()).data()];
  console.log('\nVerificación -> Auth:', mask(a.email), '| Firestore:', mask(p.email),
    '| rol:', p.rol, '| activo:', p.activo, '| emailVerified:', a.emailVerified);
  console.log('Siguiente paso: entra a la app con el correo nuevo y la MISMA contraseña,');
  console.log('pulsa «Reenviar verificación» y abre el enlace en ese buzón.');
}

main().catch((e) => fail(`Error: ${e.message}`));
