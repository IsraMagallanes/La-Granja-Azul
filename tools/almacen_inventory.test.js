// Pruebas del inventario de perfiles Almacén (solo lectura) con los emuladores
// de Firestore y Authentication y datos ficticios. Nunca toca producción: sin
// las variables de emulador la suite aborta antes de conectar.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
const { collectAlmacenInventory, formatReport } = require('./lib/almacen_inventory');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const app = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'almacen-inventory-test');
const auth = admin.auth(app);
const db = admin.firestore(app);
const Timestamp = admin.firestore.Timestamp;

let seq = 0;
const newUid = () => `almTest${Date.now()}${seq++}`;
const SECRET = { numeroDocumento: '45678912', celular: '987654321', apellidos: 'ApellidoSecreto' };

async function profile(rol, extra = {}, { withAuth = true } = {}) {
  const uid = newUid();
  if (withAuth) await auth.createUser({ uid, email: `${uid}@restaurante.test`, password: 'x'.repeat(12) });
  await db.doc(`usuarios/${uid}`).set({
    rol, activo: true, estado: 'activo', nombres: 'Rosa', email: `${uid}@restaurante.test`,
    fechaIngreso: '2026-03-01', creadoEn: Timestamp.fromDate(new Date('2026-03-01T10:00:00Z')),
    ...SECRET, ...extra,
  });
  return uid;
}

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

const find = (inv, uid) => inv.perfiles.find((p) => p.uid === uid);

test('lista solo perfiles Almacén y los distingue de otros roles', async () => {
  const a = await profile('almacen');
  const cocina = await profile('cocina');
  const inv = await collectAlmacenInventory({ auth, db });
  assert.ok(find(inv, a));
  assert.equal(find(inv, cocina), undefined);
  assert.equal(inv.resumen.almacen, inv.perfiles.length);
  assert.ok(inv.resumen.porRol.cocina >= 1);
});

test('muestra estado, fechas, jornada y referencias históricas de cada perfil', async () => {
  const uid = await profile('almacen', { activadoEn: Timestamp.fromDate(new Date('2026-03-02T08:00:00Z')) });
  await db.doc(`estadoAsistencia/${uid}`).set({ abierta: true, asistenciaId: 'a1', actualizadoEn: Timestamp.now() });
  for (let i = 0; i < 3; i++) await db.doc(`movimientosInventario/${uid}-m${i}`).set({ creadoPor: uid, creadoPorNombre: 'Rosa' });
  await db.doc(`compras/${uid}-c1`).set({ creadoPor: uid, estado: 'pendiente' });
  await db.doc(`compras/${uid}-c2`).set({ creadoPor: 'otro', recibidoPor: uid, estado: 'recibida' });
  await db.doc(`asistencias/${uid}-a`).set({ uid, origen: 'qr' });
  await db.doc(`auditoria/${uid}-au`).set({ accion: 'x', actorUid: uid, objetivo: 'o', campos: [] });
  await db.doc(`auditoria/${uid}-ob`).set({ accion: 'y', actorUid: 'jefe', objetivo: uid, campos: [] });

  const p = find(await collectAlmacenInventory({ auth, db }), uid);
  assert.equal(p.nombres, 'Rosa');
  assert.equal(p.estado, 'activo');
  assert.equal(p.activo, true);
  assert.equal(p.fechaIngreso, '2026-03-01');
  assert.equal(p.activadoEn, '2026-03-02T08:00:00.000Z');
  assert.equal(p.jornada.abierta, true);
  assert.equal(p.auth.disabled, false);
  assert.equal(p.referencias.movimientosInventario, 3);
  assert.equal(p.referencias.comprasCreadas, 1);
  assert.equal(p.referencias.comprasPendientesCreadas, 1);
  assert.equal(p.referencias.comprasRecibidas, 1);
  assert.equal(p.referencias.asistencias, 1);
  assert.equal(p.referencias.auditoriaComoActor, 1);
  assert.equal(p.referencias.auditoriaComoObjetivo, 1);
});

test('no expone documento, celular, apellidos ni el correo completo', async () => {
  const uid = await profile('almacen');
  const inv = await collectAlmacenInventory({ auth, db });
  for (const text of [formatReport(inv, 'p'), JSON.stringify(inv)]) {
    for (const secret of [SECRET.numeroDocumento, SECRET.celular, SECRET.apellidos,
      `${uid}@restaurante.test`]) {
      assert.ok(!text.includes(secret), `no debe contener ${secret}`);
    }
    assert.ok(text.includes(uid));
  }
  assert.match(find(inv, uid).auth.email, /^al•••@restaurante\.test$/);
});

test('detecta perfiles inactivos, sin cuenta Auth, sin activar y roles desconocidos', async () => {
  const baja = await profile('almacen', { activo: false, estado: 'baja', bajaTipo: 'renuncia' }, { withAuth: false });
  const variant = await profile('Almacén');
  const invalid = await profile('barista');
  const inv = await collectAlmacenInventory({ auth, db });
  const p = find(inv, baja);
  assert.equal(p.activo, false);
  assert.equal(p.bajaTipo, 'renuncia');
  assert.equal(p.auth, null);
  assert.equal(p.activadoEn, null);
  assert.equal(find(inv, variant), undefined); // rol distinto de «almacen»: se lista aparte
  const unk = inv.rolesDesconocidos;
  assert.equal(unk.find((u) => u.uid === variant).pareceAlmacen, true);
  assert.equal(unk.find((u) => u.uid === invalid).pareceAlmacen, false);
  assert.ok(inv.resumen.sinCuentaAuth >= 1 && inv.resumen.almacenInactivos >= 1);
});

test('es de solo lectura: ni Firestore ni Authentication cambian', async () => {
  await profile('almacen');
  const before = await snapshotAll();
  await collectAlmacenInventory({ auth, db });
  assert.deepEqual(await snapshotAll(), before);
});

test('el código del inventario no contiene ninguna operación de escritura', () => {
  const forbidden = [/\.set\(/, /\.update\(/, /\.delete\(/, /\.add\(\s*\{/, /\.batch\(/, /bulkWriter/,
    /runTransaction/, /deleteUser/, /createUser/, /updateUser/, /setCustomUserClaims/,
    /deleteUsers/, /importUsers/, /revokeRefreshTokens/];
  for (const file of ['lib/almacen_inventory.js', 'inventory_almacen_users.js']) {
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
  const r = spawnSync(process.execPath, [path.join(__dirname, 'inventory_almacen_users.js')],
    { env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

test('CLI: genera el informe (texto y JSON) contra el emulador sin cambiar nada', async () => {
  const uid = await profile('almacen');
  const before = await snapshotAll();
  const script = path.join(__dirname, 'inventory_almacen_users.js');
  const text = spawnSync(process.execPath, [script], { env: process.env, encoding: 'utf8' });
  assert.equal(text.status, 0, text.stderr);
  assert.match(text.stdout, /SOLO LECTURA/);
  assert.match(text.stdout, new RegExp(uid));
  const json = spawnSync(process.execPath, [script, '--json'], { env: process.env, encoding: 'utf8' });
  assert.equal(json.status, 0, json.stderr);
  assert.equal(find(JSON.parse(json.stdout), uid).uid, uid);
  assert.deepEqual(await snapshotAll(), before);
  assert.equal(spawnSync(process.execPath, [script, '--otra'], { env: process.env, encoding: 'utf8' }).status, 1);
});

test.after(async () => { await app.delete(); });
