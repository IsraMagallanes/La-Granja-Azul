// Pruebas de la eliminación de terminales con los emuladores de Firestore y
// Authentication y datos ficticios. Nunca toca producción: sin las variables de
// emulador la suite aborta antes de crear ninguna conexión.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
const {
  State, TerminalDeletionError, execute, inspect, listPending,
} = require('./lib/terminal_deletion');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const app = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'delete-terminal-test');
const auth = admin.auth(app);
const db = admin.firestore(app);
const FieldValue = admin.firestore.FieldValue;

let seq = 0;
const newUid = () => `termTest${Date.now()}${seq++}`;

/** Terminal ficticia completa: cuenta, documentos, tokens, asistencias, auditoría. */
async function seed({ activo = false, withAuth = true, tokens = 3, asistencias = 2 } = {}) {
  const uid = newUid();
  if (withAuth) {
    await auth.createUser({ uid, email: `${uid}@terminal.test`, password: 'x'.repeat(12) });
  }
  await db.doc(`terminales/${uid}`).set({
    nombre: 'Tablet ficticia', activo, autorizadoPor: 'boss', ultimaAuditoriaId: 'a0',
  });
  await db.doc(`terminalClaves/${uid}`).set({ clave: 'k'.repeat(40) });
  await db.doc(`terminalPruebas/${uid}`).set({ clave: 'k'.repeat(40) });
  for (let i = 0; i < tokens; i++) {
    await db.doc(`qrTokens/${uid}-t${i}`).set({ uid: 'w1', tipo: 'entrada', terminalId: uid });
  }
  for (let i = 0; i < asistencias; i++) {
    await db.doc(`asistencias/${uid}-a${i}`).set({ uid: 'w1', terminalId: uid, origen: 'qr' });
  }
  await db.doc(`auditoria/${uid}-au0`).set({
    accion: 'autorizar_terminal', actorUid: 'boss', actorNombre: 'Jefe', objetivo: uid, campos: [],
  });
  return uid;
}

const exists = async (p) => (await db.doc(p).get()).exists;
const authExists = async (uid) => {
  try { await auth.getUser(uid); return true; } catch (e) {
    if (e.code === 'auth/user-not-found') return false;
    throw e;
  }
};
const run = (uid) => execute({ auth, db, uid, FieldValue });

test('simulación: informa conteos y no cambia nada', async () => {
  const uid = await seed();
  const report = await inspect({ auth, db, uid });
  assert.equal(report.state, State.full);
  assert.deepEqual(report.conservar, { asistencias: 2, auditoria: 1 });
  assert.equal(report.eliminar.qrTokens, 3);
  assert.equal(report.eliminar.terminalPruebas, true);
  assert.equal(report.terminal.nombre, 'Tablet ficticia');
  assert.equal(report.auth.email, `${uid}@terminal.test`.toLowerCase());

  assert.equal(await authExists(uid), true);
  for (const p of [`terminales/${uid}`, `terminalClaves/${uid}`, `terminalPruebas/${uid}`, `qrTokens/${uid}-t0`]) {
    assert.equal(await exists(p), true, p);
  }
});

test('ejecución: elimina cuenta y datos operativos y conserva historial y auditoría', async () => {
  const uid = await seed();
  const other = await seed(); // otra terminal que no debe tocarse
  const { progress } = await run(uid);

  assert.deepEqual(progress, { cuentaAuth: true, qrTokens: 3, documentos: true });
  assert.equal(await authExists(uid), false);
  for (const p of [`terminales/${uid}`, `terminalClaves/${uid}`, `terminalPruebas/${uid}`,
    `qrTokens/${uid}-t0`, `qrTokens/${uid}-t2`]) {
    assert.equal(await exists(p), false, p);
  }
  // Historial y auditoría previa intactos: el historial NO bloquea.
  assert.equal(await exists(`asistencias/${uid}-a0`), true);
  assert.equal(await exists(`asistencias/${uid}-a1`), true);
  assert.equal(await exists(`auditoria/${uid}-au0`), true);
  // Otra terminal intacta.
  assert.equal(await authExists(other), true);
  assert.equal(await exists(`terminales/${other}`), true);
  assert.equal(await exists(`qrTokens/${other}-t0`), true);
  assert.equal(await exists(`asistencias/${other}-a0`), true);
});

test('solicitud de la app: sin ella el script se niega; con ella elimina y la borra', async () => {
  const uid = await seed();
  const report = await inspect({ auth, db, uid, requireRequest: true });
  assert.equal(report.state, State.blocked);
  assert.match(report.blockers.join(' '), /solicitud de eliminación hecha desde la app/);
  await assert.rejects(() => execute({ auth, db, uid, FieldValue, requireRequest: true }),
    TerminalDeletionError);
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminales/${uid}`), true);

  await db.doc(`solicitudesEliminacionTerminal/${uid}`).set({
    nombre: 'Tablet ficticia', solicitadoPor: 'boss', ultimaAuditoriaId: 'a1',
  });
  const pending = await listPending({ db });
  assert.ok(pending.some((p) => p.uid === uid && p.nombre === 'Tablet ficticia'));
  const ready = await inspect({ auth, db, uid, requireRequest: true });
  assert.equal(ready.state, State.full);
  assert.equal(ready.solicitud.solicitadoPor, 'boss');

  const { progress } = await execute({ auth, db, uid, FieldValue, requireRequest: true });
  assert.equal(progress.documentos, true);
  assert.equal(await authExists(uid), false);
  assert.equal(await exists(`terminales/${uid}`), false);
  assert.equal(await exists(`solicitudesEliminacionTerminal/${uid}`), false);
  assert.equal(await exists(`asistencias/${uid}-a0`), true); // el historial se conserva
  assert.ok(!(await listPending({ db })).some((p) => p.uid === uid));
});

test('la auditoría identifica al script local y usa el esquema existente', async () => {
  const uid = await seed();
  await run(uid);
  const snap = await db.collection('auditoria')
    .where('objetivo', '==', uid).where('accion', '==', 'eliminar_terminal').get();
  assert.equal(snap.size, 1);
  const entry = snap.docs[0].data();
  assert.deepEqual(Object.keys(entry).sort(),
    ['accion', 'actorNombre', 'actorUid', 'campos', 'creadoEn', 'objetivo']);
  assert.equal(entry.actorUid, 'script-local');
  assert.equal(entry.actorNombre, 'Script administrativo local');
  assert.ok(entry.creadoEn.toDate() instanceof Date);
  assert.ok(entry.campos.includes('nombre: Tablet ficticia'));
  assert.ok(entry.campos.every((c) => typeof c === 'string'));
  // Las dos entradas de este UID se conservan (la previa y la nueva).
  assert.equal((await inspect({ auth, db, uid })).conservar.auditoria, 2);
});

test('rechaza una terminal activa sin eliminar nada', async () => {
  const uid = await seed({ activo: true });
  const report = await inspect({ auth, db, uid });
  assert.equal(report.state, State.blocked);
  await assert.rejects(run(uid), (e) => e instanceof TerminalDeletionError
    && /no está inhabilitada/.test(e.message));
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminales/${uid}`), true);
  assert.equal(await exists(`qrTokens/${uid}-t0`), true);
});

test('nunca elimina una cuenta de personal, aunque tenga documento de terminal', async () => {
  const uid = await seed({ activo: false });
  await db.doc(`usuarios/${uid}`).set({ rol: 'mesero', activo: true });
  await assert.rejects(run(uid), /cuenta de personal/);
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminales/${uid}`), true);
  assert.equal(await exists(`usuarios/${uid}`), true);
});

test('rechaza una cuenta de Authentication sin documento de terminal', async () => {
  const uid = newUid();
  await auth.createUser({ uid, email: `${uid}@x.test`, password: 'x'.repeat(12) });
  await assert.rejects(run(uid), /no se puede verificar/);
  assert.equal(await authExists(uid), true);
});

test('UID inexistente: nada que eliminar y sin efectos', async () => {
  const uid = newUid();
  const report = await inspect({ auth, db, uid });
  assert.equal(report.state, State.done);
  const { progress } = await run(uid);
  assert.deepEqual(progress, { cuentaAuth: false, qrTokens: 0, documentos: false });
  assert.equal((await db.collection('auditoria').where('objetivo', '==', uid).get()).size, 0);
});

test('UID con formato no válido se rechaza', async () => {
  for (const bad of ['', 'ab', 'a/b/c/d/e/f', '../x1234', 'x'.repeat(200)]) {
    await assert.rejects(inspect({ auth, db, uid: bad }), /UID no válido/);
  }
});

test('estado parcial: Authentication ya eliminada y Firestore pendiente se completa', async () => {
  const uid = await seed({ withAuth: false });
  const report = await inspect({ auth, db, uid });
  assert.equal(report.state, State.resume);
  assert.equal(report.auth, null);

  const { progress } = await run(uid);
  assert.deepEqual(progress, { cuentaAuth: true, qrTokens: 3, documentos: true });
  assert.equal(await exists(`terminales/${uid}`), false);
  assert.equal(await exists(`terminalPruebas/${uid}`), false);
  assert.equal(await exists(`asistencias/${uid}-a0`), true);
});

test('un fallo de Firestore tras borrar Authentication informa el estado y se puede repetir', async () => {
  const uid = await seed();
  // Falla solo el lote final (el que borra terminales/{uid}).
  const realBatch = db.batch.bind(db);
  let calls = 0;
  const failing = {
    collection: (...a) => db.collection(...a),
    batch() {
      const b = realBatch();
      if (++calls < 2) return b; // primer lote: tokens
      return { delete: () => {}, set: () => {}, commit: async () => { throw new Error('fallo simulado'); } };
    },
  };
  await assert.rejects(
    execute({ auth, db: failing, uid, FieldValue }),
    (e) => {
      assert.ok(e instanceof TerminalDeletionError);
      assert.deepEqual(e.progress, { cuentaAuth: true, qrTokens: 3, documentos: false });
      assert.match(e.message, /fallo simulado/);
      return true;
    });
  // Estado real: cuenta ya eliminada, documento de terminal aún presente e inhabilitado.
  assert.equal(await authExists(uid), false);
  assert.equal(await exists(`terminales/${uid}`), true);
  assert.equal((await inspect({ auth, db, uid })).state, State.resume);

  // Repetir completa la operación una sola vez (una entrada de auditoría).
  await run(uid);
  assert.equal(await exists(`terminales/${uid}`), false);
  assert.equal(await exists(`terminalClaves/${uid}`), false);
  assert.equal(await exists(`asistencias/${uid}-a1`), true);
  const entries = await db.collection('auditoria')
    .where('objetivo', '==', uid).where('accion', '==', 'eliminar_terminal').get();
  assert.equal(entries.size, 1);
  // Y una tercera ejecución ya no encuentra nada.
  assert.equal((await inspect({ auth, db, uid })).state, State.done);
});

test('un fallo al eliminar la cuenta no toca ningún documento', async () => {
  const uid = await seed();
  const failingAuth = {
    getUser: (u) => auth.getUser(u),
    deleteUser: async () => { throw Object.assign(new Error('sin red'), { code: 'auth/internal-error' }); },
  };
  await assert.rejects(execute({ auth: failingAuth, db, uid, FieldValue }), (e) => {
    assert.deepEqual(e.progress, { cuentaAuth: false, qrTokens: 0, documentos: false });
    return true;
  });
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminales/${uid}`), true);
  assert.equal(await exists(`qrTokens/${uid}-t0`), true);
});

test('elimina más tokens QR que el tamaño de un lote', async () => {
  const uid = await seed({ tokens: 0 });
  const bulk = db.bulkWriter();
  for (let i = 0; i < 850; i++) {
    bulk.set(db.doc(`qrTokens/${uid}-b${i}`), { uid: 'w1', tipo: 'salida', terminalId: uid });
  }
  await bulk.close();
  const { progress } = await run(uid);
  assert.equal(progress.qrTokens, 850);
  assert.equal((await db.collection('qrTokens').where('terminalId', '==', uid).get()).size, 0);
});

test('los tokens sin consumir de otros trabajadores no se tocan', async () => {
  const uid = await seed({ tokens: 0 });
  await db.doc('qrTokens/pendiente-ajeno').set({ uid: 'w2', tipo: 'entrada', terminalId: null });
  await run(uid);
  assert.equal(await exists('qrTokens/pendiente-ajeno'), true);
});

test('CLI: sin credenciales ni emulador se niega y no conecta', () => {
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.FIREBASE_AUTH_EMULATOR_HOST;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  const r = spawnSync(process.execPath, [path.join(__dirname, 'delete_terminal.js'), 'abcdef123456'],
    { env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

const request = (uid) => db.doc(`solicitudesEliminacionTerminal/${uid}`)
  .set({ nombre: 'Tablet ficticia', solicitadoPor: 'boss', ultimaAuditoriaId: 'a1' });

test('CLI: sin solicitud de la app se niega; con --sin-solicitud solo simula', async () => {
  const uid = await seed();
  const script = path.join(__dirname, 'delete_terminal.js');
  const denied = spawnSync(process.execPath, [script, uid], { env: process.env, encoding: 'utf8' });
  assert.equal(denied.status, 1);
  assert.match(denied.stdout, /solicitud de eliminación hecha desde la app/);
  const manual = spawnSync(process.execPath, [script, uid, '--sin-solicitud'],
    { env: process.env, encoding: 'utf8' });
  assert.equal(manual.status, 0, manual.stderr);
  assert.equal(await authExists(uid), true);
});

test('CLI: --pendientes lista las solicitudes y no cambia nada', async () => {
  const uid = await seed();
  await request(uid);
  const r = spawnSync(process.execPath, [path.join(__dirname, 'delete_terminal.js'), '--pendientes'],
    { env: process.env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, new RegExp(uid));
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`solicitudesEliminacionTerminal/${uid}`), true);
});

test('CLI: simulación contra el emulador no elimina nada', async () => {
  const uid = await seed();
  await request(uid);
  const r = spawnSync(process.execPath, [path.join(__dirname, 'delete_terminal.js'), uid],
    { env: process.env, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /SIMULACIÓN/);
  assert.match(r.stdout, /asistencias de esta terminal : 2/);
  assert.match(r.stdout, /qrTokens de la terminal  : 3/);
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminales/${uid}`), true);
});

test('CLI: --execute sin terminal interactiva se niega', async () => {
  const uid = await seed();
  await request(uid);
  const r = spawnSync(process.execPath, [path.join(__dirname, 'delete_terminal.js'), uid, '--execute'],
    { env: process.env, encoding: 'utf8', input: '' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /terminal interactiva/);
  assert.equal(await authExists(uid), true);
});

test.after(async () => { await app.delete(); });
