#!/usr/bin/env node
/**
 * Completa la ficha de un Superadmin creado en la Fase 2 (que solo tiene
 * correo, nombre, rol y activo) con los campos de la Fase 3, SIN tocar su UID,
 * correo, rol ni `activo`.
 *
 * Por defecto es simulación (no escribe). Con --apply escribe en Firestore:
 *   - usuarios/{uid}: solo agrega campos de ficha (merge).
 *   - documentos/{numero} y correos/{email}: índices de unicidad (si no existen).
 *   - auditoria/{id}: registro de la acción.
 * No usa Auth, salvo que se pida explícitamente --verify-email (ver abajo).
 *
 * --verify-email  (opcional, con --apply): marca como verificado el correo de ESTA
 *   cuenta en Authentication. Las reglas de la Fase 3 exigen correo verificado;
 *   la cuenta creada en la Fase 2 no lo tiene. Úsalo solo si el Superadmin no
 *   puede verificarlo desde el enlace que envía la propia app. No cambia
 *   contraseña, UID, correo ni rol.
 *
 * Uso (PowerShell):
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node complete_superadmin.js                       # muestra el estado actual
 *   node complete_superadmin.js --interactive         # pide los datos por consola (simulación)
 *   node complete_superadmin.js --interactive --apply # ídem y escribe
 *   node complete_superadmin.js --nombres "Ana" --apellidos "Pérez" `
 *        --tipo dni --documento 12345678 --celular 987654321 [--ingreso 2026-01-15]
 *   (agregar --apply para escribir; --uid <uid> si hay más de un superadmin)
 */
const fs = require('node:fs');
const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'la-granja-azul-app';

function fail(message) {
  console.error(message);
  process.exit(1);
}

const answers = {};
function arg(name) {
  if (name in answers) return answers[name];
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : undefined;
}

// --interactive: pide los datos por consola (no quedan en el historial de comandos).
async function promptAnswers() {
  const rl = require('node:readline/promises').createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  const fields = [
    ['nombres', 'Nombres'],
    ['apellidos', 'Apellidos'],
    ['tipo', 'Tipo de documento (dni/ce)'],
    ['documento', 'Número de documento'],
    ['celular', 'Celular (9 dígitos, sin +51)'],
    ['ingreso', 'Fecha de ingreso yyyy-MM-dd (Enter = hoy)'],
  ];
  try {
    for (const [key, label] of fields) {
      const value = (await rl.question(`${label}: `)).trim();
      if (value) answers[key] = value;
    }
  } finally {
    rl.close();
  }
}
const flag = (name) => process.argv.includes(`--${name}`);

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
const db = admin.firestore();

const PERSON = /^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .'-]{1,59}$/;
const DOC = { dni: /^[0-9]{8}$/, ce: /^[A-Z0-9]{9,12}$/ };

async function main() {
  const snap = await db.collection('usuarios').where('rol', '==', 'superadmin').get();
  const wanted = arg('uid');
  const matches = snap.docs.filter((d) => !wanted || d.id === wanted);
  if (matches.length !== 1) {
    fail(`Se esperaba exactamente 1 superadmin y hay ${matches.length}. Usa --uid <uid>.`);
  }
  const ref = matches[0].ref;
  const current = matches[0].data();

  console.log('Proyecto:', projectId);
  console.log('UID:', ref.id);
  console.log('Estado actual -> nombre:', current.nombre, '| correo:', current.email,
    '| rol:', current.rol, '| activo:', current.activo);
  console.log('Campos presentes:', Object.keys(current).sort().join(', '));

  if (flag('interactive')) await promptAnswers();
  if (flag('verify-email') && !flag('apply')) {
    console.log('\n--verify-email solo se aplica junto con --apply.');
  }
  const nombres = arg('nombres');
  const apellidos = arg('apellidos');
  const tipo = (arg('tipo') || '').toLowerCase();
  const rawDoc = arg('documento');
  const celular = arg('celular');
  if (!nombres && !rawDoc && !celular) {
    if (flag('verify-email') && flag('apply')) {
      await admin.auth().updateUser(ref.id, { emailVerified: true });
      console.log('\nCorreo marcado como verificado en Authentication (solo ese campo).');
      return;
    }
    console.log('\n(Sin datos nuevos: solo lectura.)');
    return;
  }

  const documento = tipo === 'ce' ? (rawDoc || '').toUpperCase() : rawDoc;
  const errors = [];
  if (!nombres || !PERSON.test(nombres)) errors.push('--nombres inválido');
  if (!apellidos || !PERSON.test(apellidos)) errors.push('--apellidos inválido');
  if (!DOC[tipo]) errors.push('--tipo debe ser dni o ce');
  else if (!DOC[tipo].test(documento || '')) errors.push('--documento no cumple el formato');
  if (!/^9[0-9]{8}$/.test(celular || '')) errors.push('--celular debe tener 9 dígitos y empezar con 9');
  const ingreso = arg('ingreso') || new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10); // America/Lima = UTC-5
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ingreso)) errors.push('--ingreso debe ser yyyy-MM-dd');
  if (errors.length) fail('Datos inválidos:\n - ' + errors.join('\n - '));

  const email = String(current.email || '').toLowerCase();
  const docRef = db.collection('documentos').doc(documento);
  const mailRef = db.collection('correos').doc(email);
  const [docSnap, mailSnap] = await Promise.all([docRef.get(), mailRef.get()]);
  if (docSnap.exists && docSnap.data().uid !== ref.id) fail('Ese documento ya pertenece a otro usuario.');
  if (mailSnap.exists && mailSnap.data().uid !== ref.id) fail('Ese correo ya pertenece a otro usuario.');

  const patch = {
    nombres,
    apellidos,
    nombre: `${nombres} ${apellidos}`,
    tipoDocumento: tipo,
    numeroDocumento: documento,
    celular,
    estado: 'activo',
    fechaIngreso: ingreso,
    actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
  };
  console.log('\nSe agregará/actualizará (rol, activo, correo y UID NO se tocan):');
  console.log({ ...patch, actualizadoEn: '(hora del servidor)', numeroDocumento: '••••' + documento.slice(-2), celular: '••••••' + celular.slice(-3) });

  if (!flag('apply')) {
    console.log('\nSimulación: no se escribió nada. Repite con --apply para aplicar.');
    return;
  }

  const batch = db.batch();
  const audit = db.collection('auditoria').doc();
  batch.set(audit, {
    accion: 'completar_perfil_superadmin',
    actorUid: 'admin-sdk',
    actorNombre: 'Herramienta administrativa',
    objetivo: ref.id,
    campos: Object.keys(patch).filter((k) => k !== 'actualizadoEn'),
    creadoEn: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(ref, { ...patch, ultimaAuditoriaId: audit.id }, { merge: true });
  if (!docSnap.exists) batch.set(docRef, { uid: ref.id, creadoEn: admin.firestore.FieldValue.serverTimestamp() });
  if (!mailSnap.exists) batch.set(mailRef, { uid: ref.id, creadoEn: admin.firestore.FieldValue.serverTimestamp() });
  await batch.commit();
  if (flag('verify-email')) {
    await admin.auth().updateUser(ref.id, { emailVerified: true });
    console.log('Correo marcado como verificado en Authentication.');
  }

  const after = (await ref.get()).data();
  console.log('\nAplicado. Verificación -> rol:', after.rol, '| activo:', after.activo,
    '| correo:', after.email, '| estado:', after.estado, '| nombre:', after.nombre);
}

main().catch((e) => fail(`Error: ${e.message}`));
