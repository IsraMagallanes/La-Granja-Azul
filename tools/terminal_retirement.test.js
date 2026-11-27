// Pruebas del modo --retirar-cuenta con los emuladores de Firestore y
// Authentication y datos ficticios. Nunca toca producción: sin las variables de
// emulador la suite aborta antes de crear ninguna conexión.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
const { State, TerminalDeletionError } = require('./lib/terminal_deletion');
const { executeRetirement, inspectRetirement } = require('./lib/terminal_retirement');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const app = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'retire-terminal-test');
const auth = admin.auth(app);
const db = admin.firestore(app);
const FieldValue = admin.firestore.FieldValue;
const script = path.join(__dirname, 'delete_terminal.js');

let seq = 0;
const newUid = () => `retTest${Date.now()}${seq++}`;

/** Terminal ficticia: cuenta, documentos de enlace, tokens usados y sin usar, historial. */
async function seed({ activo = true, withAuth = true, usedTokens = 3, unusedTokens = 2 } = {}) {
  const uid = newUid();
  if (withAuth) {
    await auth.createUser({ uid, email: `${uid}@terminal.test`, password: 'x'.repeat(12) });
  }
  await db.doc(`terminales/${uid}`).set({
    nombre: 'Tablet ficticia', activo, autorizadoPor: 'boss', ultimaAuditoriaId: 'a0',
  });
  await db.doc(`terminalClaves/${uid}`).set({ clave: 'k'.repeat(40) });
  await db.doc(`terminalPruebas/${uid}`).set({ clave: 'k'.repeat(40) });
  await db.doc(`solicitudesEliminacionTerminal/${uid}`).set({ nombre: 'Tablet ficticia' });
  for (let i = 0; i < usedTokens; i++) {
    await db.doc(`qrTokens/${uid}-u${i}`).set({
      uid: 'w1', tipo: 'entrada', terminalId: uid, usadoEn: new Date(),
    });
  }
  for (let i = 0; i < unusedTokens; i++) {
    await db.doc(`qrTokens/${uid}-n${i}`).set({
      uid: 'w1', tipo: 'salida', terminalId: null, usadoEn: null, creadoEn: new Date(0),
    });
  }
  for (let i = 0; i < 2; i++) {
    await db.doc(`asistencias/${uid}-a${i}`).set({
      uid: 'w1', terminalId: uid, origen: 'qr', tokenId: `${uid}-u${i}`,
    });
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
const retire = (uid, extra = {}) => executeRetirement({ auth, db, uid, FieldValue, ...extra });
const cli = (args, opts = {}) => spawnSync(process.execPath, [script, ...args],
  { env: process.env, encoding: 'utf8', ...opts });

test('simulación: informa qué se elimina y qué se conserva y no cambia nada', async () => {
  const uid = await seed();
  const report = await inspectRetirement({ auth, db, uid });
  assert.equal(report.state, State.full);
  assert.deepEqual(report.conservar, { asistencias: 2, auditoria: 1, qrTokens: 3 });
  assert.deepEqual(report.eliminar, {
    cuentaAuth: true, terminalClaves: true, terminalPruebas: true, solicitud: true,
  });
  assert.equal(report.marcar, false);
  assert.equal(await authExists(uid), true);
  for (const p of [`terminalClaves/${uid}`, `terminalPruebas/${uid}`,
    `solicitudesEliminacionTerminal/${uid}`, `terminales/${uid}`]) {
    assert.equal(await exists(p), true, p);
  }
});

test('terminal que migra: elimina cuenta y enlace, conserva el documento intacto y no la marca', async () => {
  const uid = await seed({ activo: true });
  const before = (await db.doc(`terminales/${uid}`).get()).data();
  const { progress } = await retire(uid);

  assert.deepEqual(progress, { cuentaAuth: true, documentos: true });
  assert.equal(await authExists(uid), false);
  for (const p of [`terminalClaves/${uid}`, `terminalPruebas/${uid}`,
    `solicitudesEliminacionTerminal/${uid}`]) {
    assert.equal(await exists(p), false, p);
  }
  // El documento de la terminal queda exactamente igual: sin «retirada» y activa.
  assert.deepEqual((await db.doc(`terminales/${uid}`).get()).data(), before);
});

test('conserva TODOS los tokens (usados y sin usar), asistencias y auditoría', async () => {
  const uid = await seed({ usedTokens: 3, unusedTokens: 2 });
  await retire(uid);
  for (const p of [`qrTokens/${uid}-u0`, `qrTokens/${uid}-u2`, `qrTokens/${uid}-n0`,
    `qrTokens/${uid}-n1`, `asistencias/${uid}-a0`, `asistencias/${uid}-a1`, `auditoria/${uid}-au0`]) {
    assert.equal(await exists(p), true, p);
  }
});

test('terminal que se retira del todo (--marcar-retirada): queda inhabilitada y marcada, no borrada', async () => {
  const uid = await seed({ activo: true });
  const report = await inspectRetirement({ auth, db, uid, marcarRetirada: true });
  assert.equal(report.marcar, true);
  await retire(uid, { marcarRetirada: true });

  const doc = (await db.doc(`terminales/${uid}`).get()).data();
  assert.equal(doc.nombre, 'Tablet ficticia');
  assert.equal(doc.activo, false);
  assert.equal(doc.retirada, true);
  assert.ok(doc.retiradaEn.toDate() instanceof Date);
  assert.equal(await authExists(uid), false);
  assert.equal(await exists(`asistencias/${uid}-a0`), true);
  // Una segunda pasada no encuentra nada que hacer.
  assert.equal((await inspectRetirement({ auth, db, uid, marcarRetirada: true })).state, State.done);
});

test('no toca otras terminales ni cuentas', async () => {
  const uid = await seed();
  const other = await seed();
  await retire(uid);
  assert.equal(await authExists(other), true);
  for (const p of [`terminales/${other}`, `terminalClaves/${other}`, `terminalPruebas/${other}`,
    `qrTokens/${other}-u0`, `asistencias/${other}-a0`]) {
    assert.equal(await exists(p), true, p);
  }
});

test('la auditoría identifica al script local y usa el esquema existente', async () => {
  const uid = await seed();
  await retire(uid);
  const snap = await db.collection('auditoria')
    .where('objetivo', '==', uid).where('accion', '==', 'retirar_cuenta_terminal').get();
  assert.equal(snap.size, 1);
  const entry = snap.docs[0].data();
  assert.deepEqual(Object.keys(entry).sort(),
    ['accion', 'actorNombre', 'actorUid', 'campos', 'creadoEn', 'objetivo']);
  assert.equal(entry.actorUid, 'script-local');
  assert.ok(entry.campos.includes('nombre: Tablet ficticia'));
  assert.ok(entry.campos.includes('terminales: conservada'));
  assert.ok(entry.campos.every((c) => typeof c === 'string'));
  // La auditoría previa se conserva.
  assert.equal(await exists(`auditoria/${uid}-au0`), true);
});

test('nunca retira una cuenta de personal (trabajador, Caja, Admin, Superadmin)', async () => {
  for (const rol of ['mesero', 'cajero', 'admin', 'superadmin']) {
    const uid = await seed();
    await db.doc(`usuarios/${uid}`).set({ rol, activo: true });
    const report = await inspectRetirement({ auth, db, uid });
    assert.equal(report.state, State.blocked, rol);
    await assert.rejects(retire(uid), (e) => e instanceof TerminalDeletionError
      && /criterio 2/.test(e.message), rol);
    assert.equal(await authExists(uid), true, rol);
    assert.equal(await exists(`terminalClaves/${uid}`), true, rol);
    assert.equal(await exists(`usuarios/${uid}`), true, rol);
  }
});

test('rechaza cuentas con correo o UID en los índices de personal', async () => {
  const byMail = await seed();
  await db.doc(`correos/${byMail}@terminal.test`).set({ uid: byMail });
  await assert.rejects(retire(byMail), /criterio 3/);
  assert.equal(await authExists(byMail), true);

  const byDoc = await seed();
  await db.doc(`documentos/${byDoc}`).set({ uid: byDoc });
  await assert.rejects(retire(byDoc), /criterio 3/);
  assert.equal(await authExists(byDoc), true);
});

test('rechaza un UID que aparece como trabajador o como actor de auditoría', async () => {
  const worker = await seed();
  await db.doc(`asistencias/${worker}-w`).set({ uid: worker, origen: 'qr' });
  await assert.rejects(retire(worker), /criterio 4: aparece como trabajador/);
  assert.equal(await authExists(worker), true);

  const actor = await seed();
  await db.doc(`auditoria/${actor}-actor`).set({
    accion: 'x', actorUid: actor, actorNombre: 'x', objetivo: 'otro', campos: [],
  });
  await assert.rejects(retire(actor), /criterio 4: aparece como actor/);
  assert.equal(await authExists(actor), true);
});

test('rechaza una cuenta de Authentication sin documento de terminal', async () => {
  const uid = newUid();
  await auth.createUser({ uid, email: `${uid}@x.test`, password: 'x'.repeat(12) });
  await assert.rejects(retire(uid), /no hay documento terminales/);
  assert.equal(await authExists(uid), true);
});

test('UID inexistente: nada que retirar y sin efectos', async () => {
  const uid = newUid();
  assert.equal((await inspectRetirement({ auth, db, uid })).state, State.done);
  const { progress } = await retire(uid);
  assert.deepEqual(progress, { cuentaAuth: false, documentos: false });
  assert.equal((await db.collection('auditoria').where('objetivo', '==', uid).get()).size, 0);
});

test('UID con formato no válido se rechaza', async () => {
  for (const bad of ['', 'ab', 'a/b/c/d/e/f', '../x1234', 'x'.repeat(200)]) {
    await assert.rejects(inspectRetirement({ auth, db, uid: bad }), /UID no válido/);
  }
});

test('un fallo al eliminar la cuenta no toca ningún documento', async () => {
  const uid = await seed();
  const failingAuth = {
    getUser: (u) => auth.getUser(u),
    deleteUser: async () => { throw Object.assign(new Error('sin red'), { code: 'auth/internal-error' }); },
  };
  await assert.rejects(executeRetirement({ auth: failingAuth, db, uid, FieldValue }), (e) => {
    assert.deepEqual(e.progress, { cuentaAuth: false, documentos: false });
    return true;
  });
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminalClaves/${uid}`), true);
});

test('un fallo de Firestore tras borrar Authentication informa el estado y se puede repetir una sola vez', async () => {
  const uid = await seed();
  const realBatch = db.batch.bind(db);
  const failing = {
    collection: (...a) => db.collection(...a),
    batch: () => {
      realBatch();
      return { delete: () => {}, set: () => {}, update: () => {}, commit: async () => { throw new Error('fallo simulado'); } };
    },
  };
  await assert.rejects(
    executeRetirement({ auth, db: failing, uid, FieldValue, marcarRetirada: true }),
    (e) => {
      assert.ok(e instanceof TerminalDeletionError);
      assert.deepEqual(e.progress, { cuentaAuth: true, documentos: false });
      assert.match(e.message, /fallo simulado/);
      return true;
    });
  assert.equal(await authExists(uid), false);
  assert.equal(await exists(`terminalClaves/${uid}`), true);
  assert.equal((await inspectRetirement({ auth, db, uid, marcarRetirada: true })).state, State.resume);

  await retire(uid, { marcarRetirada: true });
  assert.equal(await exists(`terminalClaves/${uid}`), false);
  assert.equal((await db.doc(`terminales/${uid}`).get()).get('retirada'), true);
  const entries = await db.collection('auditoria')
    .where('objetivo', '==', uid).where('accion', '==', 'retirar_cuenta_terminal').get();
  assert.equal(entries.size, 1);
  assert.equal((await inspectRetirement({ auth, db, uid, marcarRetirada: true })).state, State.done);
});

test('CLI: sin credenciales ni emulador se niega y no conecta', () => {
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.FIREBASE_AUTH_EMULATOR_HOST;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  const r = cli(['abcdef123456', '--retirar-cuenta'], { env });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

test('CLI: combinaciones de opciones no válidas se rechazan', () => {
  for (const args of [
    ['abcdef123456', '--marcar-retirada'],
    ['--retirar-cuenta', '--pendientes'],
    ['abcdef123456', '--retirar-cuenta', '--sin-solicitud'],
    ['--retirar-cuenta'],
  ]) {
    const r = cli(args);
    assert.equal(r.status, 1, args.join(' '));
    assert.match(r.stderr, /Uso:/);
  }
});

test('CLI: la simulación es el modo por defecto y no cambia nada', async () => {
  const uid = await seed();
  const r = cli([uid, '--retirar-cuenta']);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /RETIRO DE CUENTA/);
  assert.match(r.stdout, /SIMULACIÓN/);
  assert.match(r.stdout, /qrTokens de la terminal      : 3 \(todos se conservan\)/);
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminalClaves/${uid}`), true);
});

test('CLI: sobre una cuenta de personal queda bloqueado y sale con error', async () => {
  const uid = await seed();
  await db.doc(`usuarios/${uid}`).set({ rol: 'cajero', activo: true });
  const r = cli([uid, '--retirar-cuenta']);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /BLOQUEADO/);
  assert.equal(await authExists(uid), true);
});

test('CLI: --execute sin terminal interactiva se niega y no elimina', async () => {
  const uid = await seed();
  const r = cli([uid, '--retirar-cuenta', '--execute'], { input: '' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /terminal interactiva/);
  assert.equal(await authExists(uid), true);
  assert.equal(await exists(`terminalClaves/${uid}`), true);
});

test.after(async () => { await app.delete(); });
