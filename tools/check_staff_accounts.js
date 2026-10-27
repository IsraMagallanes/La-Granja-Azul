#!/usr/bin/env node
/**
 * Solo lectura. Compara Authentication con Firestore y reporta, sin exponer
 * contraseñas ni enlaces: cuentas sin perfil, perfiles sin cuenta, correos que
 * no coinciden, estado de verificación y de activación.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node check_staff_accounts.js
 */
const fs = require('node:fs');
const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!keyPath) { console.error('Define GOOGLE_APPLICATION_CREDENTIALS.'); process.exit(1); }
const projectId = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
if (projectId !== EXPECTED_PROJECT) { console.error(`Proyecto inesperado: ${projectId}`); process.exit(1); }
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });

const mask = (e = '') => e.replace(/^(.{2}).*(@.*)$/, '$1•••$2');

(async () => {
  const db = admin.firestore();
  const [profiles, terminals, docs, mails] = await Promise.all(
    ['usuarios', 'terminales', 'documentos', 'correos'].map((c) => db.collection(c).get()));
  const profileBy = new Map(profiles.docs.map((d) => [d.id, d.data()]));
  const terminalIds = new Set(terminals.docs.map((d) => d.id));
  const mailIndex = new Map(mails.docs.map((d) => [d.id, d.data().uid]));
  const docIndex = new Map(docs.docs.map((d) => [d.id, d.data().uid]));

  const authUsers = [];
  let token;
  do {
    const page = await admin.auth().listUsers(1000, token);
    authUsers.push(...page.users);
    token = page.pageToken;
  } while (token);

  let problems = 0;
  const flag = (msg) => { problems++; console.log('   ⚠', msg); };
  console.log(`Authentication: ${authUsers.length} cuenta(s) | usuarios: ${profiles.size} | terminales: ${terminals.size}\n`);
  for (const u of authUsers) {
    const p = profileBy.get(u.uid);
    const kind = p ? p.rol : terminalIds.has(u.uid) ? 'terminal' : 'SIN PERFIL';
    console.log(`${kind.padEnd(11)} ${u.uid.slice(0, 6)}… ${mask(u.email)} verificado=${u.emailVerified} ` +
      `deshabilitada=${u.disabled}` + (p ? ` activo=${p.activo} activadoEn=${p.activadoEn ? 'sí' : 'no (pendiente)'}` : ''));
    if (!p && !terminalIds.has(u.uid)) flag('cuenta huérfana: existe en Authentication pero no tiene perfil ni terminal');
    if (p && String(p.email || '').toLowerCase() !== String(u.email || '').toLowerCase()) flag('el correo del perfil difiere del de Authentication');
    if (p && mailIndex.has(String(u.email || '').toLowerCase()) && mailIndex.get(String(u.email).toLowerCase()) !== u.uid) flag('el índice de correos apunta a otro UID');
    if (p && p.numeroDocumento && docIndex.get(p.numeroDocumento) !== u.uid) flag('el índice de documentos no coincide con el perfil');
  }
  const authIds = new Set(authUsers.map((u) => u.uid));
  for (const [uid, p] of profileBy) {
    if (!authIds.has(uid)) { console.log(`PERFIL SIN CUENTA ${uid.slice(0, 6)}… ${mask(p.email)}`); flag('perfil sin cuenta en Authentication'); }
  }
  console.log(problems ? `\n${problems} hallazgo(s).` : '\nSin hallazgos: todas las cuentas tienen su perfil y coinciden.');
})().catch((e) => { console.error('Error:', e.message); process.exit(1); });
