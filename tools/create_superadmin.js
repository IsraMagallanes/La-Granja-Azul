#!/usr/bin/env node
/**
 * Crea (o promueve) el PRIMER Superadmin. Solo para ejecutarse desde un
 * entorno administrativo de confianza (tu equipo), nunca desde la app.
 *
 * Credenciales: clave de cuenta de servicio indicada en la variable de entorno
 * GOOGLE_APPLICATION_CREDENTIALS (ruta fuera del repositorio). El script solo
 * lee el campo `project_id` para comprobar que apunta al proyecto correcto;
 * nunca imprime ni copia el contenido de la clave.
 *
 * Uso (PowerShell):
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node create_superadmin.js
 *
 * Nombre, correo y contraseña se piden por consola (la contraseña sin eco) y
 * no se guardan en ningún sitio.
 */
const fs = require('node:fs');
const readline = require('node:readline');
const { Writable } = require('node:stream');
const admin = require('firebase-admin');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const MIN_PASSWORD = 8;

function fail(message) {
  console.error(message);
  process.exit(1);
}

function projectIdOfKey(keyPath) {
  try {
    return JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
  } catch {
    return undefined;
  }
}

/** Pregunta por consola; con `hidden` no muestra lo que se escribe. */
function ask(question, { hidden = false } = {}) {
  let muted = false;
  const output = new Writable({
    write(chunk, _enc, cb) {
      if (!muted) process.stdout.write(chunk);
      cb();
    },
  });
  const rl = readline.createInterface({ input: process.stdin, output, terminal: true });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write('\n');
      resolve(hidden ? answer : answer.trim());
    });
    muted = hidden;
  });
}

async function main() {
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath || !fs.existsSync(keyPath)) {
    fail('Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la clave de servicio.');
  }
  if (projectIdOfKey(keyPath) !== EXPECTED_PROJECT) {
    fail(`La clave no pertenece al proyecto ${EXPECTED_PROJECT}. Abortando.`);
  }

  const nombre = await ask('Nombre completo: ');
  const email = (await ask('Correo: ')).toLowerCase();
  if (!nombre) fail('El nombre es obligatorio.');
  if (!EMAIL_RE.test(email)) fail('Correo no válido.');

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: EXPECTED_PROJECT,
  });
  const auth = admin.auth();
  const db = admin.firestore();

  let user;
  try {
    user = await auth.getUserByEmail(email);
    console.log('La cuenta ya existe; se asignará el rol superadmin (la contraseña no cambia).');
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    const password = await ask(`Contraseña (mín. ${MIN_PASSWORD} caracteres): `, { hidden: true });
    const confirm = await ask('Repite la contraseña: ', { hidden: true });
    if (password.length < MIN_PASSWORD) fail('Contraseña demasiado corta.');
    if (password !== confirm) fail('Las contraseñas no coinciden.');
    user = await auth.createUser({ email, password, displayName: nombre });
  }

  await db.collection('usuarios').doc(user.uid).set(
    {
      email,
      nombre,
      rol: 'superadmin',
      activo: true,
      creadoEn: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log(`Superadmin listo: ${email} (uid ${user.uid})`);
}

main().catch((e) => fail(e.message || String(e)));
