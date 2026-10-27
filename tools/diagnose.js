#!/usr/bin/env node
/**
 * Diagnóstico de solo lectura: compara Authentication con Firestore para un
 * correo y muestra qué reglas están publicadas. No escribe nada.
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\clave.json'
 *   node diagnose.js correo@dominio
 */
const fs = require('node:fs');
const crypto = require('node:crypto');
const admin = require('firebase-admin');

const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!keyPath) throw new Error('Define GOOGLE_APPLICATION_CREDENTIALS');
const projectId = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
if (projectId !== 'la-granja-azul-app') throw new Error(`Proyecto inesperado: ${projectId}`);
admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });

(async () => {
  const email = process.argv[2];
  if (email) {
    const user = await admin.auth().getUserByEmail(email);
    console.log('Auth      -> uid:', user.uid, '| disabled:', user.disabled, '| verificado:', user.emailVerified);
    const snap = await admin.firestore().collection('usuarios').doc(user.uid).get();
    console.log('Firestore -> existe usuarios/{uid}:', snap.exists);
    if (snap.exists) {
      const d = snap.data();
      console.log('            rol:', d.rol, '| activo:', d.activo, '| campos:', Object.keys(d).sort().join(', '));
    }
  }
  const all = await admin.firestore().collection('usuarios').get();
  console.log('Documentos en usuarios:', all.size, all.docs.map((d) => `${d.id.slice(0, 6)}…(${d.data().rol})`).join(', '));

  const rs = await admin.securityRules().getFirestoreRuleset();
  const source = rs.source[0].content;
  const local = fs.readFileSync(require('node:path').join(__dirname, '..', 'firestore.rules'), 'utf8');
  const norm = (t) => t.replace(/\r\n/g, '\n').trim();
  const hash = (t) => crypto.createHash('sha256').update(norm(t)).digest('hex').slice(0, 12);
  console.log('Reglas publicadas -> creadas:', rs.createTime, '| hash:', hash(source),
    '| líneas:', norm(source).split('\n').length);
  console.log('Reglas locales    -> hash:', hash(local), '| líneas:', norm(local).split('\n').length);
  console.log('¿Coinciden?', hash(source) === hash(local));
  console.log('Publicadas incluyen reglas de Fase 3 (movimientosPersonal)?', source.includes('movimientosPersonal'));
})().catch((e) => { console.error('Error:', e.message); process.exit(1); });
