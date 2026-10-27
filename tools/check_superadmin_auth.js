#!/usr/bin/env node
/**
 * Solo lectura. Muestra si la cuenta Superadmin ya verificó su correo en
 * Authentication y si es seguro publicar las reglas que exigen `email_verified`.
 * No escribe nada ni marca nada como verificado.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node check_superadmin_auth.js
 */
const fs = require('node:fs');
const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!keyPath) { console.error('Define GOOGLE_APPLICATION_CREDENTIALS.'); process.exit(1); }
const projectId = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
if (projectId !== EXPECTED_PROJECT) { console.error(`Proyecto inesperado: ${projectId}`); process.exit(1); }

admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });

(async () => {
  const snap = await admin.firestore().collection('usuarios').get();
  const staff = snap.docs.map((d) => ({ uid: d.id, ...d.data() }));
  let blocked = 0;
  for (const u of staff.filter((x) => x.activo === true)) {
    let auth;
    try { auth = await admin.auth().getUser(u.uid); } catch { auth = null; }
    const ok = auth && auth.emailVerified && !auth.disabled;
    if (!ok) blocked++;
    console.log(`${u.rol.padEnd(10)} ${u.uid.slice(0, 6)}… correo=${u.email} ` +
      (auth ? `emailVerified=${auth.emailVerified} disabled=${auth.disabled}` : 'SIN CUENTA EN AUTH') +
      (ok ? '  OK' : '  <- quedaría sin acceso con reglas restrictivas'));
  }
  const supers = staff.filter((x) => x.rol === 'superadmin' && x.activo === true);
  console.log(blocked === 0
    ? '\nSeguro endurecer: todas las cuentas activas tienen el correo verificado.'
    : `\nNO publicar aún las reglas con email_verified: ${blocked} cuenta(s) activa(s) sin verificar.`);
  if (!supers.length) console.log('Advertencia: no hay Superadmin activo.');
})().catch((e) => { console.error('Error:', e.message); process.exit(1); });
