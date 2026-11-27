// Pruebas del inventario de cuentas de terminal (solo lectura) con los
// emuladores de Firestore y Authentication y datos ficticios. Nunca toca
// producción: sin las variables de emulador la suite aborta antes de conectar.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
const { Verdict, collectInventory, formatReport } = require('./lib/terminal_inventory');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const app = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'inventory-test');
const auth = admin.auth(app);
const db = admin.firestore(app);

let seq = 0;
const newUid = () => `invTest${Date.now()}${seq++}`;
const find = (inv, uid) => inv.cuentas.find((a) => a.uid === uid);

async function terminal({ withAuth = true, activo = true, extra = async () => {} } = {}) {
  const uid = newUid();
  if (withAuth) await auth.createUser({ uid, email: `${uid}@terminal.test`, password: 'x'.repeat(12) });
  await db.doc(`terminales/${uid}`).set({ nombre: `Tablet ${uid}`, activo });
  await db.doc(`terminalClaves/${uid}`).set({ clave: 'k'.repeat(40) });
  await db.doc(`qrTokens/${uid}-u`).set({ uid: 'w1', tipo: 'entrada', terminalId: uid, usadoEn: new Date() });
  await db.doc(`asistencias/${uid}-a`).set({ uid: 'w1', terminalId: uid, origen: 'qr', tokenId: `${uid}-u` });
  await extra(uid);
  return uid;
}

async function staff(rol) {
  const uid = newUid();
  await auth.createUser({ uid, email: `${uid}@staff.test`, password: 'x'.repeat(12) });
  await db.doc(`usuarios/${uid}`).set({ rol, activo: true, email: `${uid}@staff.test` });
  await db.doc(`correos/${uid}@staff.test`).set({ uid });
  return uid;
}

/** Estado completo de Firestore (todas las colecciones) y de Authentication. */
async function snapshotAll() {
  const state = {};
  for (const col of await db.listCollections()) {
    for (const d of (await col.get()).docs) state[`${col.id}/${d.id}`] = JSON.stringify(d.data());
  }
  const users = [];
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    users.push(...page.users.map((u) => `${u.uid}|${u.email}|${u.disabled}`));
    token = page.pageToken;
  } while (token);
  return { state, users: users.sort() };
}

test('clasifica terminales exclusivas, excluye personal y detecta cuentas sin Auth', async () => {
  const exclusive = await terminal();
  const noAuth = await terminal({ withAuth: false });
  const cajero = await terminal({ extra: async (uid) => db.doc(`usuarios/${uid}`).set({ rol: 'cajero', activo: true }) });
  const mailIndexed = await terminal({ extra: async (uid) => db.doc(`correos/${uid}@terminal.test`).set({ uid }) });
  const worker = await terminal({ extra: async (uid) => db.doc(`asistencias/${uid}-w`).set({ uid, origen: 'qr' }) });
  const actor = await terminal({
    extra: async (uid) => db.doc(`auditoria/${uid}-x`).set({ accion: 'x', actorUid: uid, objetivo: 'o', campos: [] }),
  });
  const orphan = newUid();
  await auth.createUser({ uid: orphan, email: `${orphan}@x.test`, password: 'x'.repeat(12) });
  const normal = await staff('mesero');

  const inv = await collectInventory({ auth, db });
  assert.equal(find(inv, exclusive).verdict, Verdict.exclusive);
  assert.equal(find(inv, noAuth).verdict, Verdict.documentsOnly);
  for (const [uid, motivo] of [[cajero, /criterio 2/], [mailIndexed, /criterio 3/],
    [worker, /criterio 4: aparece como trabajador/], [actor, /criterio 4: aparece como actor/],
    [orphan, /criterio 1/]]) {
    const a = find(inv, uid);
    assert.equal(a.verdict, Verdict.excluded, uid);
    assert.match(a.reasons.join(' '), motivo, uid);
  }
  // Una cuenta normal sin documento de terminal no es candidata ni se lista.
  assert.equal(find(inv, normal), undefined);
  assert.ok(inv.resumen.cuentasNormalesIgnoradas >= 1);
  assert.equal(inv.resumen.candidatas,
    inv.resumen.terminalesExclusivas + inv.resumen.excluidas + inv.resumen.sinCuentaAuth);
});

test('muestra los datos solicitados por cuenta y enmascara el correo', async () => {
  const uid = await terminal();
  await db.doc(`solicitudesEliminacionTerminal/${uid}`).set({ nombre: 'x' });
  await db.doc(`auditoria/${uid}-obj`).set({ accion: 'autorizar_terminal', actorUid: 'boss', objetivo: uid, campos: [] });
  const inv = await collectInventory({ auth, db });
  const a = find(inv, uid);

  assert.equal(a.nombre, `Tablet ${uid}`);
  assert.equal(a.activo, true);
  assert.match(a.auth.email, /^in•••@terminal\.test$/);
  assert.equal(a.auth.disabled, false);
  assert.deepEqual(a.documentos, {
    terminales: true, terminalClaves: true, terminalPruebas: false, solicitudEliminacion: true,
  });
  assert.deepEqual(a.referencias, {
    asistenciasComoTerminal: 1, auditoriaComoObjetivo: 1, qrTokensUsados: 1,
  });
  const text = formatReport(inv, 'p');
  assert.match(text, new RegExp(`UID        : ${uid}`));
  assert.ok(!text.includes(`${uid}@terminal.test`), 'no debe imprimir el correo completo');
  assert.match(text, /SOLO LECTURA/);
});

test('resume los qrTokens: usados, sin usar, vencidos y referencias', async () => {
  const before = (await collectInventory({ auth, db })).tokens;
  const uid = newUid();
  await db.doc(`qrTokens/${uid}-used`).set({ uid: 'w', tipo: 'entrada', terminalId: uid, usadoEn: new Date() });
  await db.doc(`qrTokens/${uid}-old`).set({ uid: 'w', tipo: 'entrada', terminalId: null, usadoEn: null, creadoEn: new Date(0) });
  await db.doc(`qrTokens/${uid}-fresh`).set({ uid: 'w', tipo: 'salida', terminalId: null, usadoEn: null, creadoEn: new Date() });
  // Anomalía: una asistencia que apunta a un token sin usar.
  await db.doc(`asistencias/${uid}-bad`).set({ uid: 'w', origen: 'qr', tokenId: `${uid}-old` });

  const t = (await collectInventory({ auth, db })).tokens;
  assert.equal(t.total - before.total, 3);
  assert.equal(t.usados - before.usados, 1);
  assert.equal(t.sinUsar - before.sinUsar, 2);
  assert.equal(t.sinUsarVencidos - before.sinUsarVencidos, 1);
  assert.equal(t.sinUsarVigentes - before.sinUsarVigentes, 1);
  assert.equal(t.sinUsarPorTipo.salida - before.sinUsarPorTipo.salida, 1);
  assert.equal(t.asistenciasQueReferencianTokensSinUsar
    - before.asistenciasQueReferencianTokensSinUsar, 1);
  assert.equal(t.referenciasSinRevisar, 0);
});

test('es de solo lectura: ni Firestore ni Authentication cambian', async () => {
  await terminal();
  await staff('admin');
  const before = await snapshotAll();
  await collectInventory({ auth, db });
  const after = await snapshotAll();
  assert.deepEqual(after, before);
});

test('el código del inventario no contiene ninguna operación de escritura', () => {
  const forbidden = [/\.set\(/, /\.update\(/, /\.delete\(/, /\.add\(\s*\{/, /\.batch\(/, /bulkWriter/,
    /runTransaction/, /deleteUser/, /createUser/, /updateUser/, /setCustomUserClaims/,
    /deleteUsers/, /importUsers/, /revokeRefreshTokens/];
  for (const file of ['lib/terminal_inventory.js', 'lib/terminal_criteria.js',
    'inventory_terminal_accounts.js']) {
    const source = fs.readFileSync(path.join(__dirname, file), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const re of forbidden) assert.doesNotMatch(source, re, `${file} contiene ${re}`);
  }
});

test('CLI: sin credenciales ni emulador se niega y no conecta', () => {
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.FIREBASE_AUTH_EMULATOR_HOST;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  const r = spawnSync(process.execPath, [path.join(__dirname, 'inventory_terminal_accounts.js')],
    { env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

test('CLI: genera el informe (texto y JSON) contra el emulador sin cambiar nada', async () => {
  const uid = await terminal();
  const before = await snapshotAll();
  const script = path.join(__dirname, 'inventory_terminal_accounts.js');
  const text = spawnSync(process.execPath, [script], { env: process.env, encoding: 'utf8' });
  assert.equal(text.status, 0, text.stderr);
  assert.match(text.stdout, /TERMINAL EXCLUSIVA/);
  assert.match(text.stdout, new RegExp(uid));
  const json = spawnSync(process.execPath, [script, '--json'], { env: process.env, encoding: 'utf8' });
  assert.equal(json.status, 0, json.stderr);
  assert.equal(find(JSON.parse(json.stdout), uid).verdict, Verdict.exclusive);
  assert.deepEqual(await snapshotAll(), before);
  const bad = spawnSync(process.execPath, [script, '--otra'], { env: process.env, encoding: 'utf8' });
  assert.equal(bad.status, 1);
});

test.after(async () => { await app.delete(); });
