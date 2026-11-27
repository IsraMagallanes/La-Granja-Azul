// Pruebas de la migración de costos de insumos con el emulador de Firestore y
// datos ficticios. Nunca toca producción: sin la variable de emulador la suite
// aborta antes de crear ninguna conexión. La lógica usa su propio proyecto
// (`demo-migrate-costs`) para no mezclarse con las demás suites.
//
//   npm run test:rules   (levanta los emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const admin = require('firebase-admin');
const {
  MigrationError, State, executeMigration, inspectMigration,
} = require('./lib/supply_costs_migration');

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen el emulador de Firestore ' +
    '(FIRESTORE_EMULATOR_HOST). Abortando.');
}

const PROJECT = 'demo-migrate-costs';
const app = admin.initializeApp({ projectId: PROJECT }, 'migrate-costs-test');
const db = admin.firestore(app);
const FieldValue = admin.firestore.FieldValue;
const script = path.join(__dirname, 'migrate_supply_costs.js');

const clear = () => fetch(
  `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
  { method: 'DELETE' });

const insumo = (extra = {}) => ({
  nombre: 'Pollo', unidad: 'kg', stock: 5000, stockMinimo: 1000, costoUnitario: 1200,
  activo: true, ultimoMovimiento: 'm0', ...extra,
});

/** Estado completo y comparable de la base. */
async function snapshot() {
  const state = {};
  for (const col of await db.listCollections()) {
    for (const d of (await col.get()).docs) state[`${col.id}/${d.id}`] = JSON.stringify(d.data());
  }
  return state;
}

/** Diferencias entre dos instantáneas: documentos añadidos, cambiados y borrados. */
function diff(before, after) {
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  const out = { added: [], changed: [], removed: [] };
  for (const k of keys) {
    if (!(k in before)) out.added.push(k);
    else if (!(k in after)) out.removed.push(k);
    else if (before[k] !== after[k]) out.changed.push(k);
  }
  return out;
}

/** Datos típicos: 2 insumos con costo, una compra recibida y sus 2 movimientos. */
async function seed() {
  await db.doc('insumos/i1').set(insumo());
  await db.doc('insumos/i2').set(insumo({ nombre: 'Arroz', costoUnitario: 350, stock: 0 }));
  await db.doc('insumos/i3').set({
    nombre: 'Sal', unidad: 'kg', stock: 0, stockMinimo: 0, activo: true, ultimoMovimiento: 'm0',
  });
  await db.doc('compras/c1').set({
    proveedorId: 'p1', estado: 'recibida', creadoPor: 'u1',
    lineas: [
      { insumoId: 'i1', cantidad: 2000, costoUnitario: 1200, subtotal: 2400 },
      { insumoId: 'i2', cantidad: 5000, costoUnitario: 350, subtotal: 1750 },
    ],
  });
  await db.doc('movimientosInventario/c1_0').set({
    insumoId: 'i1', tipo: 'compra', delta: 2000, compraId: 'c1', linea: 0, costoUnitario: 1200, motivo: '',
  });
  await db.doc('movimientosInventario/c1_1').set({
    insumoId: 'i2', tipo: 'compra', delta: 5000, compraId: 'c1', linea: 1, costoUnitario: 350, motivo: '',
  });
  await db.doc('movimientosInventario/m_otro').set({
    insumoId: 'i1', tipo: 'salida', delta: -100, motivo: 'merma de prueba',
  });
  await db.doc('proveedores/p1').set({ nombre: 'Avícola' });
}

test.beforeEach(clear);

test('simulación: informa lo previsto y no cambia nada', async () => {
  await seed();
  const before = await snapshot();
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.migrate);
  assert.deepEqual(r.counts, {
    insumos: 3, aCopiar: 2, yaCopiados: 0, insumosALimpiar: 2, movimientosALimpiar: 2, conflictos: 0,
  });
  assert.deepEqual(await snapshot(), before);
});

test('ejecución: copia los costos y quita solo ese campo, sin tocar nada más', async () => {
  await seed();
  const before = await snapshot();
  const { progress } = await executeMigration({ db, FieldValue });
  assert.deepEqual(progress, { copiados: 2, insumosLimpios: 2, movimientosLimpios: 2, auditoria: true });

  assert.equal((await db.doc('costosInsumos/i1').get()).get('costoUnitario'), 1200);
  assert.equal((await db.doc('costosInsumos/i2').get()).get('costoUnitario'), 350);
  assert.equal((await db.doc('costosInsumos/i3').get()).exists, false);

  const after = await snapshot();
  const d = diff(before, after);
  assert.deepEqual(d.removed, []);
  assert.deepEqual(d.added.filter((k) => !k.startsWith('auditoria/')).sort(),
    ['costosInsumos/i1', 'costosInsumos/i2']);
  assert.equal(d.added.filter((k) => k.startsWith('auditoria/')).length, 1);
  assert.deepEqual(d.changed.sort(), [
    'insumos/i1', 'insumos/i2', 'movimientosInventario/c1_0', 'movimientosInventario/c1_1']);

  // Los documentos modificados son idénticos salvo el campo costoUnitario.
  for (const key of d.changed) {
    const was = JSON.parse(before[key]);
    delete was.costoUnitario;
    assert.deepEqual(JSON.parse(after[key]), was, key);
  }
  // Intactos: insumo sin costo, movimiento no de compra, compra y proveedor.
  for (const key of ['insumos/i3', 'movimientosInventario/m_otro', 'compras/c1', 'proveedores/p1']) {
    assert.equal(after[key], before[key], key);
  }
});

test('el costo queda en la colección protegida con el esquema esperado', async () => {
  await seed();
  await executeMigration({ db, FieldValue });
  const cost = (await db.doc('costosInsumos/i1').get()).data();
  assert.deepEqual(Object.keys(cost).sort(), ['actualizadoEn', 'actualizadoPor', 'costoUnitario']);
  assert.equal(cost.actualizadoPor, 'migracion');
  assert.ok(cost.actualizadoEn.toDate() instanceof Date);
});

test('la auditoría usa el esquema existente y se registra una sola vez', async () => {
  await seed();
  await executeMigration({ db, FieldValue });
  const snap = await db.collection('auditoria').where('accion', '==', 'migrar_costos_insumos').get();
  assert.equal(snap.size, 1);
  const entry = snap.docs[0].data();
  assert.deepEqual(Object.keys(entry).sort(),
    ['accion', 'actorNombre', 'actorUid', 'campos', 'creadoEn', 'objetivo']);
  assert.equal(entry.actorUid, 'script-local');
  assert.ok(entry.campos.every((c) => typeof c === 'string'));
  assert.ok(entry.campos.includes('costos copiados: 2'));
});

test('idempotente: repetirla no cambia nada ni añade auditoría', async () => {
  await seed();
  await executeMigration({ db, FieldValue });
  const settled = await snapshot();
  assert.equal((await inspectMigration({ db })).state, State.done);
  const { progress } = await executeMigration({ db, FieldValue });
  assert.deepEqual(progress, { copiados: 0, insumosLimpios: 0, movimientosLimpios: 0, auditoria: false });
  assert.deepEqual(await snapshot(), settled);
});

test('verificación contra las compras: un costo que no coincide bloquea todo', async () => {
  await seed();
  await db.doc('movimientosInventario/c1_1').update({ costoUnitario: 999 });
  const before = await snapshot();
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.blocked);
  assert.match(r.conflicts.join(' '), /c1_1.*no coincide con la línea/);
  await assert.rejects(executeMigration({ db, FieldValue }), (e) => e instanceof MigrationError
    && e.progress.copiados === 0);
  assert.deepEqual(await snapshot(), before); // ni siquiera se copió el resto
});

test('verificación: compra inexistente, línea inexistente e insumo distinto', async () => {
  await seed();
  await db.doc('movimientosInventario/x1').set({ insumoId: 'i1', tipo: 'compra', compraId: 'nada', linea: 0, costoUnitario: 1 });
  await db.doc('movimientosInventario/x2').set({ insumoId: 'i1', tipo: 'compra', compraId: 'c1', linea: 7, costoUnitario: 1200 });
  await db.doc('movimientosInventario/x3').set({ insumoId: 'i2', tipo: 'compra', compraId: 'c1', linea: 0, costoUnitario: 1200 });
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.blocked);
  const text = r.conflicts.join('\n');
  assert.match(text, /x1.*no existe/);
  assert.match(text, /x2.*línea 7/);
  assert.match(text, /x3.*insumo no coincide/);
});

test('conflicto: un costo ya existente y distinto no se sobrescribe', async () => {
  await seed();
  await db.doc('costosInsumos/i1').set({ costoUnitario: 777, actualizadoEn: new Date(0), actualizadoPor: 'admin1' });
  const before = await snapshot();
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.blocked);
  assert.match(r.conflicts.join(' '), /costosInsumos\/i1 con un costo distinto/);
  await assert.rejects(executeMigration({ db, FieldValue }), MigrationError);
  assert.deepEqual(await snapshot(), before);
});

test('un costo ya copiado e idéntico no se reescribe', async () => {
  await seed();
  await db.doc('costosInsumos/i1').set({ costoUnitario: 1200, actualizadoEn: new Date(0), actualizadoPor: 'admin1' });
  const r = await inspectMigration({ db });
  assert.equal(r.counts.yaCopiados, 1);
  assert.equal(r.counts.aCopiar, 1);
  await executeMigration({ db, FieldValue });
  const kept = (await db.doc('costosInsumos/i1').get()).data();
  assert.equal(kept.actualizadoPor, 'admin1'); // intacto
  assert.equal((await db.doc('insumos/i1').get()).get('costoUnitario'), undefined);
});

test('costos no válidos y movimientos no de compra con costo bloquean', async () => {
  await seed();
  await db.doc('insumos/malo1').set(insumo({ costoUnitario: -5 }));
  await db.doc('insumos/malo2').set(insumo({ costoUnitario: '12' }));
  await db.doc('insumos/malo3').set(insumo({ costoUnitario: 12.5 }));
  await db.doc('insumos/malo4').set(insumo({ costoUnitario: 10000001 }));
  await db.doc('movimientosInventario/raro').set({ insumoId: 'i1', tipo: 'salida', costoUnitario: 100 });
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.blocked);
  assert.equal(r.conflicts.length, 5);
  assert.match(r.conflicts.join(' '), /raro.*no es de compra/);
});

test('reanudable: copias y limpieza parcial se completan sin duplicar', async () => {
  await seed();
  // Simula una ejecución interrumpida: costos copiados y un insumo ya limpio.
  for (const [id, c] of [['i1', 1200], ['i2', 350]]) {
    await db.doc(`costosInsumos/${id}`).set({ costoUnitario: c, actualizadoEn: new Date(0), actualizadoPor: 'migracion' });
  }
  await db.doc('insumos/i1').update({ costoUnitario: FieldValue.delete() });
  const r = await inspectMigration({ db });
  assert.deepEqual(r.counts, {
    insumos: 3, aCopiar: 0, yaCopiados: 1, insumosALimpiar: 1, movimientosALimpiar: 2, conflictos: 0,
  });
  const { progress } = await executeMigration({ db, FieldValue });
  assert.deepEqual(progress, { copiados: 0, insumosLimpios: 1, movimientosLimpios: 2, auditoria: true });
  assert.equal((await inspectMigration({ db })).state, State.done);
});

test('si un documento cambia entre la lectura y la limpieza, esa operación falla y se puede repetir', async () => {
  await seed();
  let updated = false;
  let patched = false;
  const racing = {
    collection: (...a) => db.collection(...a),
    batch() {
      const batch = db.batch();
      const update = batch.update.bind(batch);
      const commit = batch.commit.bind(batch);
      batch.update = (...args) => { updated = true; return update(...args); };
      batch.commit = async () => {
        if (updated && !patched) {
          patched = true;
          await db.doc('insumos/i1').update({ stockMinimo: 4242 }); // alguien edita el insumo
        }
        return commit();
      };
      return batch;
    },
  };
  await assert.rejects(executeMigration({ db: racing, FieldValue }), (e) => {
    assert.ok(e instanceof MigrationError);
    assert.equal(e.progress.copiados, 2);
    assert.equal(e.progress.auditoria, false);
    return true;
  });
  // El documento editado conserva su cambio y su costo; no hay auditoría aún.
  const edited = (await db.doc('insumos/i1').get()).data();
  assert.equal(edited.stockMinimo, 4242);
  assert.equal(edited.costoUnitario, 1200);
  assert.equal((await db.collection('auditoria').get()).size, 0);

  await executeMigration({ db, FieldValue }); // repetir completa
  const done = (await db.doc('insumos/i1').get()).data();
  assert.equal(done.stockMinimo, 4242);
  assert.equal(done.costoUnitario, undefined);
  assert.equal((await inspectMigration({ db })).state, State.done);
});

test('procesa más documentos que el tamaño de un lote', async () => {
  const bulk = db.bulkWriter();
  for (let i = 0; i < 450; i++) bulk.set(db.doc(`insumos/b${i}`), insumo({ costoUnitario: i + 1 }));
  await bulk.close();
  const { progress } = await executeMigration({ db, FieldValue });
  assert.equal(progress.copiados, 450);
  assert.equal(progress.insumosLimpios, 450);
  assert.equal((await db.collection('costosInsumos').get()).size, 450);
  assert.equal((await db.collection('insumos').where('costoUnitario', '>=', 0).get()).size, 0);
});

test('informa de las compras pendientes con más de 5 líneas sin tocarlas', async () => {
  await seed();
  const line = (n) => ({ insumoId: `i${n}`, cantidad: 1, costoUnitario: 1, subtotal: 0 });
  await db.doc('compras/grande').set({ estado: 'pendiente', lineas: [1, 2, 3, 4, 5, 6].map(line) });
  await db.doc('compras/justa').set({ estado: 'pendiente', lineas: [1, 2, 3, 4, 5].map(line) });
  await db.doc('compras/vieja').set({ estado: 'recibida', lineas: [1, 2, 3, 4, 5, 6, 7].map(line) });
  const before = await db.doc('compras/grande').get();
  const r = await inspectMigration({ db });
  assert.deepEqual(r.oversizedPending, ['grande']);
  await executeMigration({ db, FieldValue });
  assert.deepEqual((await db.doc('compras/grande').get()).data(), before.data());
});

test('sin datos: nada que migrar', async () => {
  const r = await inspectMigration({ db });
  assert.equal(r.state, State.done);
  assert.deepEqual((await executeMigration({ db, FieldValue })).progress,
    { copiados: 0, insumosLimpios: 0, movimientosLimpios: 0, auditoria: false });
  assert.equal((await db.collection('auditoria').get()).size, 0);
});

test('el script solo escribe donde corresponde (revisión del código)', () => {
  const source = fs.readFileSync(path.join(__dirname, 'lib/supply_costs_migration.js'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.doesNotMatch(source, /(?<!FieldValue)\.delete\(/); // nunca borra documentos (solo el campo)
  assert.doesNotMatch(source, /batch\.set\(/);          // solo `create` y `update` de un campo
  assert.doesNotMatch(source, /runTransaction|bulkWriter|recursiveDelete/);
  assert.doesNotMatch(source, /createUser|deleteUser|updateUser/);
});

test('CLI: sin credenciales ni emulador se niega y no conecta', () => {
  const env = { ...process.env };
  delete env.FIRESTORE_EMULATOR_HOST;
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  const r = spawnSync(process.execPath, [script], { env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

test('CLI: opciones desconocidas se rechazan', () => {
  const r = spawnSync(process.execPath, [script, '--otra'], { env: process.env, encoding: 'utf8' });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Uso:/);
});

test('CLI: la simulación es el modo por defecto y --execute exige terminal interactiva', async () => {
  // El script usa el proyecto de producción por nombre; contra el emulador es
  // un espacio aislado, que se limpia antes y después.
  const real = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'migrate-cli-test');
  const rdb = admin.firestore(real);
  const wipe = () => fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/la-granja-azul-app/databases/(default)/documents`,
    { method: 'DELETE' });
  try {
    await wipe();
    await rdb.doc('insumos/cli1').set(insumo());
    const sim = spawnSync(process.execPath, [script], { env: process.env, encoding: 'utf8' });
    assert.equal(sim.status, 0, sim.stderr);
    assert.match(sim.stdout, /SIMULACIÓN/);
    assert.match(sim.stdout, /Costos por copiar a costosInsumos\s+: 1/);
    assert.equal((await rdb.doc('insumos/cli1').get()).get('costoUnitario'), 1200);

    const exec = spawnSync(process.execPath, [script, '--execute'],
      { env: process.env, encoding: 'utf8', input: '' });
    assert.equal(exec.status, 1);
    assert.match(exec.stderr, /terminal interactiva/);
    assert.equal((await rdb.doc('insumos/cli1').get()).get('costoUnitario'), 1200);
    assert.equal((await rdb.doc('costosInsumos/cli1').get()).exists, false);

    // Con conflictos la simulación sale con error y lo explica.
    await rdb.doc('costosInsumos/cli1').set({ costoUnitario: 5, actualizadoEn: new Date(0), actualizadoPor: 'x' });
    const blocked = spawnSync(process.execPath, [script], { env: process.env, encoding: 'utf8' });
    assert.equal(blocked.status, 1);
    assert.match(blocked.stdout, /CONFLICTOS/);
  } finally {
    await wipe();
    await real.delete();
  }
});

test.after(async () => {
  await clear();
  await app.delete();
});
