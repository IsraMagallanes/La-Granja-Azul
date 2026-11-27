// Reglas de insumos, recetas, proveedores y compras. Cocina gestiona los insumos;
// proveedores, compras, recetas y costos son solo de Admin y Superadmin. Los
// costos viven en `costosInsumos` (Cocina nunca los lee) y la recepción de una
// compra valida el costo de cada línea contra esa colección (opción B), con un
// máximo de 5 líneas por compra. Incluye la regresión de la auditoría de seguridad.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-inv', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });

const db = (uid, verified = true) => env.authenticatedContext(uid, { email_verified: verified }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const now = () => serverTimestamp();
const old = () => Timestamp.fromDate(new Date('2026-01-01T00:00:00Z'));
const NAMES = { i1: 'Pollo', i2: 'Papa' };
const nameOf = (id) => NAMES[id] ?? id;

async function seedSupplies(extra = 0) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'insumos/i1'), { nombre: 'Pollo', unidad: 'kg', stock: 10000, stockMinimo: 2000,
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'insumos/i2'), { nombre: 'Papa', unidad: 'kg', stock: 5000, stockMinimo: 1000,
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'costosInsumos/i1'), { costoUnitario: 1200, actualizadoEn: Timestamp.now(), actualizadoPor: 'admin' });
    await setDoc(doc(d, 'costosInsumos/i2'), { costoUnitario: 300, actualizadoEn: Timestamp.now(), actualizadoPor: 'admin' });
    for (let i = 3; i < 3 + extra; i++) {
      await setDoc(doc(d, 'insumos', `i${i}`), { nombre: `i${i}`, unidad: 'kg', stock: 1000, stockMinimo: 0,
        activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    }
  });
}

async function seedBase() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ k: 'cocina', k2: 'cocina', koff: 'cocina', w1: 'mesero',
      cash: 'cajero', admin: 'admin', admin2: 'admin', super: 'superadmin', inactive: 'cocina' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: uid !== 'inactive' });
    }
    for (const uid of ['k', 'k2', 'w1', 'cash', 'inactive']) {
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: true, asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'estadoAsistencia', 'koff'), { abierta: false, asistenciaId: 'akoff' });
    await setDoc(doc(d, 'proveedores/p1'), { nombre: 'Avícola Sur', ruc: '20123456789', telefono: '999', contacto: 'Luis',
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'proveedores/p2'), { nombre: 'Inactivo SAC', ruc: '', telefono: '', contacto: '',
      activo: false, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'carta/d1'), { nombre: 'Pollo a la brasa', precio: 25, disponible: true });
  });
  await seedSupplies();
}
beforeEach(seedBase);

const STOCK = ['k', 'admin', 'super']; // quienes gestionan insumos
const NO_STOCK = ['w1', 'cash', 'inactive', 'koff'];
const ADMINS = ['admin', 'admin2', 'super'];

const newSupply = (extra = {}) => ({ nombre: 'Aceite', unidad: 'l', stock: 0, stockMinimo: 1000,
  activo: true, creadoEn: now(), actualizadoEn: now(), ...extra });

function movement(uid, supply, tipo, delta, result, extra = {}) {
  return { insumoId: supply, insumoNombre: nameOf(supply), tipo, delta, stockResultante: result, motivo: 'Conteo del día',
    creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...extra };
}
// Movimiento manual: stock del insumo + su movimiento, en un solo lote.
function adjust(database, uid, { id = 'm1', supply = 'i1', before = 10000, tipo = 'entrada', delta = 2000, result, move = {}, patch = {} } = {}) {
  const batch = writeBatch(database);
  const stock = result ?? before + delta;
  batch.set(doc(database, 'movimientosInventario', id), movement(uid, supply, tipo, delta, stock, move));
  batch.update(doc(database, 'insumos', supply), { stock, ultimoMovimiento: id, actualizadoEn: now(), ...patch });
  return batch.commit();
}

// ------------------------------------------------------------------- insumos
test('cocina, admin y superadmin crean insumos (sin costo); el resto no', async () => {
  for (const uid of STOCK) await assertSucceeds(setDoc(doc(db(uid), 'insumos', `n-${uid}`), newSupply()));
  for (const uid of NO_STOCK) await assertFails(setDoc(doc(db(uid), 'insumos', 'x'), newSupply()));
  await assertFails(setDoc(doc(anon(), 'insumos', 'x'), newSupply()));
  await assertFails(setDoc(doc(db('k', false), 'insumos', 'x'), newSupply()));
});

test('insumo nuevo inválido: stock inicial, unidad, valores, costo y campos', async () => {
  for (const extra of [{ stock: 5 }, { unidad: 'caja' }, { nombre: 'a' }, { nombre: '  ' }, { stockMinimo: -1 }, { stockMinimo: 1.5 },
    { costoUnitario: 800 }, { costoUnitario: 0 }, { activo: 'si' }, { creadoEn: Timestamp.now() }, { extra: 1 }]) {
    await assertFails(setDoc(doc(db('k'), 'insumos', 'x'), newSupply(extra)));
  }
});

test('edición del catálogo: nombre, mínimo y activo; nunca stock, unidad ni costo', async () => {
  for (const uid of STOCK) {
    await assertSucceeds(updateDoc(doc(db(uid), 'insumos/i1'), { nombre: 'Pollo entero', stockMinimo: 3000, activo: false, actualizadoEn: now() }));
  }
  await assertFails(updateDoc(doc(db('k'), 'insumos/i2'), { costoUnitario: 1, actualizadoEn: now() }));
  for (const uid of ADMINS) await assertFails(updateDoc(doc(db(uid), 'insumos/i2'), { costoUnitario: 350, actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { stock: 99999, actualizadoEn: now() })); // sin movimiento
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { unidad: 'g', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { nombre: 'x', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { stockMinimo: -5, actualizadoEn: now() }));
  for (const uid of NO_STOCK) await assertFails(updateDoc(doc(db(uid), 'insumos/i1'), { nombre: 'Hackeado', actualizadoEn: now() }));
  for (const uid of [...STOCK, 'admin2']) await assertFails(deleteDoc(doc(db(uid), 'insumos/i1')));
});

test('un insumo antiguo con costoUnitario sigue editable, pero nadie puede cambiarlo ni reintroducirlo', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { costoUnitario: 1200 }));
  await assertSucceeds(updateDoc(doc(db('k'), 'insumos/i1'), { nombre: 'Pollo 2', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { costoUnitario: 1, actualizadoEn: now() }));
  await assertSucceeds(adjust(db('k'), 'k', { move: { insumoNombre: 'Pollo 2' } })); // el stock se mueve igual
});

test('lectura: insumos, movimientos, recetas y descuentos para Cocina y administración; costos y compras solo la administración', async () => {
  for (const uid of STOCK) {
    for (const c of ['insumos', 'recetas', 'movimientosInventario', 'descuentosInventario']) await assertSucceeds(getDocs(collection(db(uid), c)));
  }
  for (const uid of ADMINS) {
    for (const c of ['proveedores', 'compras', 'costosInsumos']) await assertSucceeds(getDocs(collection(db(uid), c)));
  }
  for (const c of ['proveedores', 'compras', 'costosInsumos', 'excepcionesInventario']) await assertFails(getDocs(collection(db('k'), c)));
  await assertFails(getDoc(doc(db('k'), 'costosInsumos/i1')));
  for (const uid of NO_STOCK) {
    for (const c of ['insumos', 'recetas', 'costosInsumos', 'proveedores', 'compras', 'movimientosInventario']) {
      await assertFails(getDocs(collection(db(uid), c)));
    }
  }
  await assertFails(getDocs(collection(anon(), 'insumos')));
});

// --------------------------------------------------------------- movimientos
test('entrada, salida, merma y ajuste dejan stock y movimiento consistentes', async () => {
  await assertSucceeds(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000 }));
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 12000);
  const m = (await getDoc(doc(f, 'movimientosInventario/m1'))).data();
  assert.equal(m.delta, 2000); assert.equal(m.creadoPor, 'k'); assert.ok(m.creadoEn);
  assert.equal('costoUnitario' in m, false);
});

test('todo movimiento manual exige motivo, también la entrada, y respeta el signo', async () => {
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, move: { motivo: '' } }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, move: { motivo: 'ab' } }));
  await assertSucceeds(adjust(db('k'), 'k', { tipo: 'salida', delta: -3000 }));
  await assertFails(adjust(db('k'), 'k', { id: 'm2', tipo: 'salida', delta: 3000, before: 7000 })); // signo
  await assertFails(adjust(db('k'), 'k', { id: 'm2', tipo: 'entrada', delta: -3000, before: 7000 }));
  await assertFails(adjust(db('k'), 'k', { id: 'm2', tipo: 'merma', delta: 100, before: 7000 }));
  await assertFails(adjust(db('k'), 'k', { id: 'm2', tipo: 'merma', delta: -100, before: 7000, move: { motivo: '' } }));
  await assertFails(adjust(db('k'), 'k', { id: 'm2', tipo: 'ajuste', delta: -100, before: 7000, move: { motivo: 'ab' } }));
  await assertSucceeds(adjust(db('admin'), 'admin', { id: 'm3', tipo: 'ajuste', delta: -100, before: 7000 }));
});

test('el stock no puede quedar negativo ni inconsistente con el movimiento', async () => {
  await assertFails(adjust(db('k'), 'k', { tipo: 'salida', delta: -10001 })); // negativo
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, result: 99999 })); // stock distinto
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, move: { stockResultante: 1 } }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 0 }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 1.5 }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, patch: { ultimoMovimiento: 'otro' } }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, patch: { nombre: 'x' } }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 2000, move: { insumoNombre: 'Falso' } }));
});

test('un movimiento sin cambio de stock, o un cambio de stock sin movimiento, se rechaza', async () => {
  const d = db('k');
  await assertFails(setDoc(doc(d, 'movimientosInventario', 'solo'), movement('k', 'i1', 'entrada', 2000, 12000)));
  const batch = writeBatch(d);
  batch.update(doc(d, 'insumos', 'i1'), { stock: 12000, ultimoMovimiento: 'fantasma', actualizadoEn: now() });
  await assertFails(batch.commit());
});

test('movimientos: identidad, hora, campos y roles; son de solo agregar', async () => {
  for (const move of [{ creadoPor: 'k2' }, { creadoPorNombre: 'Falso' }, { creadoEn: Timestamp.now() }, { extra: 1 },
    { tipo: 'otro' }, { insumoId: 'i2' }, { motivo: 'x'.repeat(121) }, { compraId: 'c1' }, { linea: 0 }, { costoUnitario: 1 }]) {
    await assertFails(adjust(db('k'), 'k', { move }));
  }
  for (const uid of NO_STOCK) await assertFails(adjust(db(uid), uid));
  await assertSucceeds(adjust(db('k'), 'k'));
  for (const uid of STOCK) {
    await assertFails(updateDoc(doc(db(uid), 'movimientosInventario/m1'), { delta: 1 }));
    await assertFails(deleteDoc(doc(db(uid), 'movimientosInventario/m1')));
  }
});

test('Cocina no puede registrar un movimiento de tipo compra (ni siquiera con una compra pendiente)', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('k'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'k', recibidoPorNombre: 'Usuario k', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/c1_0'), movement('k', 'i1', 'compra', 1000, 11000, { motivo: '', compraId: 'c1', linea: 0 }));
  b.update(doc(d, 'insumos/i1'), { stock: 11000, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  await assertFails(b.commit());
});

test('un insumo desactivado no recibe movimientos', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { activo: false }));
  await assertFails(adjust(db('k'), 'k'));
});

// -------------------------------------------------------------------- costos
const cost = (uid, extra = {}) => ({ costoUnitario: 900, actualizadoEn: now(), actualizadoPor: uid, ...extra });

test('costosInsumos: solo la administración escribe y lee; sin borrado', async () => {
  for (const uid of ADMINS) {
    await assertSucceeds(setDoc(doc(db(uid), 'costosInsumos/i1'), cost(uid)));
    await assertSucceeds(setDoc(doc(db(uid), 'costosInsumos/nuevo'), cost(uid, { costoUnitario: 0 }))); // 0 = sin costo
    await assertSucceeds(getDoc(doc(db(uid), 'costosInsumos/i1')));
    await assertFails(deleteDoc(doc(db(uid), 'costosInsumos/i1')));
  }
  for (const uid of ['k', 'k2', ...NO_STOCK]) {
    await assertFails(setDoc(doc(db(uid), 'costosInsumos/i1'), cost(uid)));
    await assertFails(getDoc(doc(db(uid), 'costosInsumos/i1')));
    await assertFails(getDocs(collection(db(uid), 'costosInsumos')));
  }
  await assertFails(getDoc(doc(anon(), 'costosInsumos/i1')));
});

test('costosInsumos: forma, hora y autor', async () => {
  const a = db('admin');
  for (const extra of [{ costoUnitario: -1 }, { costoUnitario: 1.5 }, { costoUnitario: 'x' }, { costoUnitario: 10000001 },
    { actualizadoEn: Timestamp.now() }, { actualizadoPor: 'admin2' }, { extra: 1 }]) {
    await assertFails(setDoc(doc(a, 'costosInsumos/i1'), cost('admin', extra)));
  }
  await assertFails(setDoc(doc(a, 'costosInsumos/i1'), { costoUnitario: 1, actualizadoEn: now() })); // falta autor
});

// --------------------------------------------------------------- proveedores
const supplier = (extra = {}) => ({ nombre: 'Nuevo SAC', ruc: '20999999999', telefono: '987654321', contacto: 'Ana',
  activo: true, creadoEn: now(), actualizadoEn: now(), ...extra });

test('proveedores: solo Admin y Superadmin; alta, edición y desactivación; sin borrado', async () => {
  for (const uid of ADMINS) await assertSucceeds(setDoc(doc(db(uid), 'proveedores', `n-${uid}`), supplier()));
  await assertSucceeds(setDoc(doc(db('admin'), 'proveedores', 'sinruc'), supplier({ ruc: '' })));
  for (const extra of [{ nombre: 'a' }, { ruc: '123' }, { ruc: 'abcdefghijk' }, { telefono: 'x'.repeat(21) }, { activo: 1 }, { extra: 1 }]) {
    await assertFails(setDoc(doc(db('admin'), 'proveedores', 'bad'), supplier(extra)));
  }
  for (const uid of ['k', ...NO_STOCK]) await assertFails(setDoc(doc(db(uid), 'proveedores', 'bad'), supplier()));
  await assertSucceeds(setDoc(doc(db('admin'), 'proveedores/p1'), supplier({ creadoEn: (await getDoc(doc(db('admin'), 'proveedores/p1'))).data().creadoEn, activo: false })));
  await assertFails(setDoc(doc(db('k'), 'proveedores/p1'), supplier({ creadoEn: (await getDoc(doc(db('admin'), 'proveedores/p1'))).data().creadoEn })));
  await assertFails(deleteDoc(doc(db('admin'), 'proveedores/p1')));
});

// ------------------------------------------------------------------- compras
const subtotal = (qty, cost) => Math.round((qty * cost) / 1000);
const line = (id, qty = 4000, cost = 1250, extra = {}) => ({ insumoId: id, nombre: nameOf(id), cantidad: qty, costoUnitario: cost, subtotal: subtotal(qty, cost), ...extra });
const purchase = (uid, extra = {}) => {
  const lineas = extra.lineas ?? [line('i1')];
  return { proveedorId: 'p1', proveedorNombre: 'Avícola Sur', lineas,
    estado: 'pendiente', creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...extra };
};

test('compra: solo Admin y Superadmin, pendiente, con proveedor activo y líneas válidas', async () => {
  for (const uid of ADMINS) await assertSucceeds(setDoc(doc(db(uid), 'compras', `c-${uid}`), purchase(uid)));
  await assertSucceeds(setDoc(doc(db('admin'), 'compras', 'dos'), purchase('admin', { lineas: [line('i1'), line('i2', 2000, 350)] })));
  for (const uid of ['k', ...NO_STOCK]) await assertFails(setDoc(doc(db(uid), 'compras', 'x'), purchase(uid)));
});

test('compra inválida a nivel de documento', async () => {
  for (const extra of [{ proveedorId: 'p2', proveedorNombre: 'Inactivo SAC' }, { proveedorId: 'nada' }, { lineas: [] }, { total: 5000 }, // el total no se guarda
    { estado: 'recibida' }, { creadoPor: 'admin2' }, { creadoPorNombre: 'Falso' }, { creadoEn: Timestamp.now() }, { extra: 1 },
    { proveedorNombre: 'Otro proveedor falso' }]) {
    await assertFails(setDoc(doc(db('admin'), 'compras', 'bad'), purchase('admin', extra)));
  }
});

test('cada línea se valida: insumo, cantidad, costo, subtotal y orden', async () => {
  const bad = (lineas) => assertFails(setDoc(doc(db('admin'), 'compras', 'bad'), purchase('admin', { lineas })));
  await bad([line('i1', -5)]); // cantidad negativa
  await bad([line('i1', 0)]);
  await bad([line('i1', 1.5)]);
  await bad([line('i1', 4000, -1)]);
  await bad([line('i1', 4000, 1.5)]);
  await bad([line('i1', 4000, 'x')]);
  await bad([line('i1', 4000, 1250, { subtotal: 1 })]); // subtotal falso
  await bad([line('i1', 4000, 1250, { subtotal: 99999 })]);
  await bad([line('i1', 4000, 1250, { subtotal: -5 })]);
  await bad([line('i1'), line('i1')]); // repetido
  await bad([line('i2', 2000, 350), line('i1')]); // desordenado
  await bad(['texto', 42]); // basura
});

async function seedPurchase(lines = [line('i1', 4000, 1250), line('i2', 2000, 350)], by = 'admin') {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'compras/c1'), { proveedorId: 'p1', proveedorNombre: 'Avícola Sur',
    lineas: lines, estado: 'pendiente', creadoPor: by, creadoPorNombre: `Usuario ${by}`, creadoEn: Timestamp.now() }));
}
// Recibe la compra c1: su cambio de estado + por línea un movimiento (c1_n), el
// stock del insumo y el costo de la línea en costosInsumos (opción B).
function receive(database, uid, { compra = 'c1', lines = [['i1', 4000, 10000, 1250], ['i2', 2000, 5000, 350]], skipPurchase = false,
  purchasePatch = {}, move = {}, supplyPatch = {}, skipCost = false, costPatch = {} } = {}) {
  const batch = writeBatch(database);
  if (!skipPurchase) {
    batch.update(doc(database, 'compras', compra), { estado: 'recibida', recibidoPor: uid, recibidoPorNombre: `Usuario ${uid}`, recibidoEn: now(), ...purchasePatch });
  }
  lines.forEach(([id, qty, before, unitCost], n) => {
    const mid = `${compra}_${n}`;
    batch.set(doc(database, 'movimientosInventario', mid), movement(uid, id, 'compra', qty, before + qty,
      { motivo: '', compraId: compra, linea: n, ...move }));
    batch.update(doc(database, 'insumos', id), { stock: before + qty, ultimoMovimiento: mid, actualizadoEn: now(), ...supplyPatch });
    if (!skipCost) batch.set(doc(database, 'costosInsumos', id), { costoUnitario: unitCost, actualizadoEn: now(), actualizadoPor: uid, ...costPatch });
  });
  return batch.commit();
}

// Por el límite de expresiones de las reglas (1000 por evaluación) el insumo de cada línea
// no se consulta al crear la compra: se exige al recibirla, cuando el movimiento lo valida.
test('una línea con insumo inexistente, desactivado o de otro insumo no se puede recibir', async () => {
  const cases = [[line('noexiste', 1000, 100), 'noexiste'], [line('i1', 1000, 100), 'i2']];
  for (const [l, id] of cases) {
    await seedBase();
    await seedPurchase([l]);
    await assertFails(receive(db('admin2'), 'admin2', { lines: [[id, 1000, 10000, 100]] }));
  }
  await seedBase();
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { activo: false }));
  await seedPurchase([line('i1', 1000, 100)]);
  await assertFails(receive(db('admin2'), 'admin2', { lines: [['i1', 1000, 10000, 100]] }));
});

test('una compra admite como máximo 5 líneas', async () => {
  await seedSupplies(6);
  const ids = ['i1', 'i2', 'i3', 'i4', 'i5', 'i6', 'i7', 'i8'];
  await assertSucceeds(setDoc(doc(db('admin'), 'compras', 'cinco'), purchase('admin', { lineas: ids.slice(0, 5).map((i) => line(i, 1000, 100)) })));
  await assertFails(setDoc(doc(db('admin'), 'compras', 'seis'), purchase('admin', { lineas: ids.slice(0, 6).map((i) => line(i, 1000, 100)) })));
  await assertFails(setDoc(doc(db('admin'), 'compras', 'ocho'), purchase('admin', { lineas: ids.map((i) => line(i, 1000, 100)) })));
});

test('recibir una compra la cierra y suma stock y costo de cada línea, en un solo lote', async () => {
  await seedPurchase();
  await assertSucceeds(receive(db('admin2'), 'admin2'));
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'compras/c1'))).data().estado, 'recibida');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 14000);
  assert.equal((await getDoc(doc(f, 'insumos/i2'))).data().stock, 7000);
  assert.equal((await getDoc(doc(f, 'costosInsumos/i1'))).data().costoUnitario, 1250);
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().costoUnitario, undefined);
  assert.equal((await getDoc(doc(f, 'movimientosInventario/c1_1'))).data().linea, 1);
});

test('solo Admin y Superadmin reciben compras; Cocina y el resto no', async () => {
  await seedPurchase();
  for (const uid of ['k', 'k2', ...NO_STOCK]) await assertFails(receive(db(uid), uid));
  // quien crea la compra (Admin) también puede recibirla
  await assertSucceeds(receive(db('admin'), 'admin'));
  for (const uid of ['admin2', 'super']) {
    await seedBase();
    await seedPurchase([line('i1', 4000, 1250)], uid);
    await assertSucceeds(receive(db(uid), uid, { lines: [['i1', 4000, 10000, 1250]] }));
  }
});

test('recibir exige el movimiento de cada línea, con cantidad, insumo y costo de la línea', async () => {
  await seedPurchase();
  await assertFails(receive(db('admin'), 'admin', { lines: [] })); // sin movimientos
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 4000, 10000, 1250]] })); // falta la línea 2
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 4000, 10000, 1250], ['i2', 2001, 5000, 350]] })); // cantidad distinta
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 4000, 10000, 1], ['i2', 2000, 5000, 350]] })); // costo distinto
  await assertFails(receive(db('admin'), 'admin', { lines: [['i2', 2000, 5000, 350], ['i1', 4000, 10000, 1250]] })); // insumos cruzados
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'compras/c1'))).data().estado, 'pendiente');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 10000);
  assert.equal((await getDoc(doc(f, 'costosInsumos/i1'))).data().costoUnitario, 1200); // sin cambios
});

test('opción B: el costo de la línea debe quedar en costosInsumos al recibir', async () => {
  await seedPurchase([line('i1', 4000, 1250)]);
  const one = [['i1', 4000, 10000, 1250]];
  // sin escribir el costo: el de costosInsumos (1200) no coincide con la línea (1250)
  await assertFails(receive(db('admin'), 'admin', { lines: one, skipCost: true }));
  // costo distinto del de la línea
  await assertFails(receive(db('admin'), 'admin', { lines: one, costPatch: { costoUnitario: 1 } }));
  await assertSucceeds(receive(db('admin'), 'admin', { lines: one }));
  assert.equal((await getDoc(doc(db('admin'), 'costosInsumos/i1'))).data().costoUnitario, 1250);
});

test('opción B: si el costo ya coincide con la línea no hace falta reescribirlo', async () => {
  await seedPurchase([line('i1', 4000, 1200)]);
  await assertSucceeds(receive(db('admin'), 'admin', { lines: [['i1', 4000, 10000, 1200]], skipCost: true }));
});

test('recibir: stock resultante y movimiento deben coincidir con la línea', async () => {
  await seedPurchase([line('i1', 4000, 1250)]);
  const one = [['i1', 4000, 10000, 1250]];
  await assertFails(receive(db('admin'), 'admin', { lines: one, supplyPatch: { costoUnitario: 1250 } })); // el insumo ya no lleva costo
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { costoUnitario: 1250 } })); // ni el movimiento
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { stockResultante: 1 } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { tipo: 'entrada' } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { motivo: 'algo' } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { linea: 1 } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, move: { compraId: 'otra' } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, purchasePatch: { recibidoPor: 'admin2' } }));
  await assertFails(receive(db('admin'), 'admin', { lines: one, purchasePatch: { total: 1 } }));
  await assertFails(receive(db('w1'), 'w1', { lines: one }));
  await assertSucceeds(receive(db('admin'), 'admin', { lines: one }));
});

test('una compra pendiente de más de 5 líneas (anterior) no se puede recibir; sí cancelar', async () => {
  await seedSupplies(6);
  const ids = ['i1', 'i2', 'i3', 'i4', 'i5', 'i6', 'i7', 'i8'];
  const stocks = { i1: 10000, i2: 5000 };
  await seedPurchase(ids.slice(0, 6).map((i) => line(i, 1000, 100)));
  await assertFails(receive(db('admin'), 'admin', { lines: ids.slice(0, 6).map((i) => [i, 1000, stocks[i] ?? 1000, 100]) }));
  await assertFails(receive(db('admin'), 'admin', { lines: ids.slice(0, 5).map((i) => [i, 1000, stocks[i] ?? 1000, 100]) })); // omitir líneas
  await assertSucceeds(updateDoc(doc(db('admin'), 'compras/c1'), { estado: 'cancelada', canceladoPor: 'admin',
    canceladoPorNombre: 'Usuario admin', canceladoEn: now(), motivoCancelacion: 'Rehacer en dos compras' }));
});

test('una compra no se recibe dos veces ni después de cancelada', async () => {
  await seedPurchase();
  await assertSucceeds(receive(db('admin2'), 'admin2'));
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 4000, 14000, 1250], ['i2', 2000, 7000, 350]] }));
  await seedPurchase();
  const cancel = (extra = {}) => updateDoc(doc(db('admin'), 'compras/c1'), { estado: 'cancelada', canceladoPor: 'admin',
    canceladoPorNombre: 'Usuario admin', canceladoEn: now(), motivoCancelacion: 'Proveedor sin stock', ...extra });
  await assertFails(cancel({ motivoCancelacion: 'ab' }));
  await assertFails(cancel({ canceladoPor: 'admin2' }));
  await assertFails(updateDoc(doc(db('k'), 'compras/c1'), { estado: 'cancelada', canceladoPor: 'k', canceladoPorNombre: 'Usuario k',
    canceladoEn: now(), motivoCancelacion: 'Proveedor sin stock' }));
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'compras/c1'), { estado: 'pendiente' }));
  await assertSucceeds(cancel());
  await assertFails(receive(db('admin2'), 'admin2'));
  await assertFails(updateDoc(doc(db('admin'), 'compras/c1'), { estado: 'pendiente' }));
  await assertFails(deleteDoc(doc(db('admin'), 'compras/c1')));
});

// ------------------------------------------------------------------- recetas
test('recetas: solo administración escribe; Cocina las lee; de un plato existente y bien formadas', async () => {
  const ing = (extra = {}) => ({ insumoId: 'i1', nombre: 'Pollo', cantidad: 500, ...extra });
  const recipe = (uid, extra = {}) => ({ ingredientes: [ing()], actualizadoPor: uid, actualizadoEn: now(), ...extra });
  for (const uid of ADMINS) await assertSucceeds(setDoc(doc(db(uid), 'recetas/d1'), recipe(uid)));
  await assertSucceeds(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { ingredientes: [] })));
  await assertFails(setDoc(doc(db('admin'), 'recetas/inexistente'), recipe('admin')));
  await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin2')));
  await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { actualizadoEn: Timestamp.now() })));
  await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { ingredientes: Array.from({ length: 31 }, () => ing()) })));
  await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { extra: 1 })));
  await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { costoUnitario: 1 }))); // la receta no lleva costos
  for (const bad of [['texto'], [ing({ cantidad: -1 })], [ing({ cantidad: 0 })], [ing({ cantidad: 1.5 })], [ing({ cantidad: 'x' })], [ing({ extra: 1 })], [ing({ costoUnitario: 5 })], [{ insumoId: 'i1' }], 42]) {
    await assertFails(setDoc(doc(db('admin'), 'recetas/d1'), recipe('admin', { ingredientes: bad })));
  }
  for (const uid of ['k', ...NO_STOCK]) await assertFails(setDoc(doc(db(uid), 'recetas/d1'), recipe(uid)));
  await assertSucceeds(getDocs(collection(db('k'), 'recetas')));
  await assertFails(deleteDoc(doc(db('admin'), 'recetas/d1')));
});

test('sin jornada abierta Cocina pierde los insumos; el admin no', async () => {
  await assertFails(adjust(db('koff'), 'koff'));
  await assertFails(getDocs(collection(db('koff'), 'insumos')));
  await assertSucceeds(adjust(db('admin'), 'admin'));
});

// =============================================================================
// Regresión de la auditoría de seguridad (2026-11-19): los 17 intentos de
// manipulación del sondeo, adaptados al modelo actual (Cocina/Admin, costos aparte).
// =============================================================================
const audit = test;

audit('A. Reescribir el stock apuntando a un movimiento histórico, sin movimiento nuevo', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'movimientosInventario/old'), { insumoId: 'i1', insumoNombre: 'Pollo',
    tipo: 'entrada', delta: 1, stockResultante: 50000, motivo: 'viejo', creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: old() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { stock: 50000, ultimoMovimiento: 'old', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('admin'), 'insumos/i1'), { stock: 50000, ultimoMovimiento: 'old', actualizadoEn: now() }));
});

audit('A2. Lo mismo bajando el stock a 0 con un movimiento histórico', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'movimientosInventario/zero'), { insumoId: 'i1', insumoNombre: 'Pollo',
    tipo: 'salida', delta: -1, stockResultante: 0, motivo: 'viejo', creadoPor: 'k', creadoPorNombre: 'x', creadoEn: old() }));
  await assertFails(updateDoc(doc(db('k'), 'insumos/i1'), { stock: 0, ultimoMovimiento: 'zero', actualizadoEn: now() }));
});

audit('A3. Un movimiento nuevo no sirve para otro insumo ni para dos insumos a la vez', async () => {
  const d = db('k'); const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/n1'), movement('k', 'i1', 'entrada', 2000, 12000));
  b.update(doc(d, 'insumos/i1'), { stock: 12000, ultimoMovimiento: 'n1', actualizadoEn: now() });
  b.update(doc(d, 'insumos/i2'), { stock: 7000, ultimoMovimiento: 'n1', actualizadoEn: now() }); // reutiliza el mismo movimiento
  await assertFails(b.commit());
});

audit('B. Recibir una compra de una línea y sumar stock a un insumo que no está en ella', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('admin2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/x1'), movement('admin2', 'i2', 'compra', 900000, 905000, { motivo: '', compraId: 'c1', linea: 0 }));
  b.update(doc(d, 'insumos/i2'), { stock: 905000, ultimoMovimiento: 'x1', actualizadoEn: now() });
  await assertFails(b.commit());
  // con el id correcto de la línea pero del insumo equivocado
  const b2 = writeBatch(d);
  b2.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() });
  b2.set(doc(d, 'movimientosInventario/c1_0'), movement('admin2', 'i2', 'compra', 1000, 6000, { motivo: '', compraId: 'c1', linea: 0 }));
  b2.update(doc(d, 'insumos/i2'), { stock: 6000, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  b2.set(doc(d, 'costosInsumos/i2'), { costoUnitario: 100, actualizadoEn: now(), actualizadoPor: 'admin2' });
  await assertFails(b2.commit());
});

audit('B2. Un movimiento «compra» que en realidad baja el stock con un resultante falso', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  for (const [delta, result] of [[1, 0], [1000, 0], [1000, 12000]]) {
    const d = db('admin2'); const b = writeBatch(d);
    b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() });
    b.set(doc(d, 'movimientosInventario/c1_0'), movement('admin2', 'i1', 'compra', delta, result, { motivo: '', compraId: 'c1', linea: 0 }));
    b.update(doc(d, 'insumos/i1'), { stock: result, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
    b.set(doc(d, 'costosInsumos/i1'), { costoUnitario: 100, actualizadoEn: now(), actualizadoPor: 'admin2' });
    await assertFails(b.commit());
  }
});

audit('B3. Sumar una cantidad distinta de la comprada', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await assertFails(receive(db('admin2'), 'admin2', { lines: [['i1', 500000, 10000, 100]] }));
  await assertSucceeds(receive(db('admin2'), 'admin2', { lines: [['i1', 1000, 10000, 100]] }));
});

audit('B4. Fijar costos de insumos sin relación con la compra, en el mismo lote', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('admin2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/c1_0'), movement('admin2', 'i1', 'compra', 1000, 11000, { motivo: '', compraId: 'c1', linea: 0 }));
  b.update(doc(d, 'insumos/i1'), { stock: 11000, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  b.set(doc(d, 'costosInsumos/i1'), { costoUnitario: 1, actualizadoEn: now(), actualizadoPor: 'admin2' }); // costo ≠ línea
  b.set(doc(d, 'movimientosInventario/x2'), movement('admin2', 'i2', 'compra', 1, 5001, { motivo: '', compraId: 'c1', linea: 1 }));
  b.update(doc(d, 'insumos/i2'), { stock: 5001, ultimoMovimiento: 'x2', actualizadoEn: now() });
  b.set(doc(d, 'costosInsumos/i2'), { costoUnitario: 9999900, actualizadoEn: now(), actualizadoPor: 'admin2' });
  await assertFails(b.commit());
});

audit('C. Recibir la compra sin ningún movimiento', async () => {
  await seedPurchase();
  await assertFails(updateDoc(doc(db('admin2'), 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() }));
});

audit('D. Compra con líneas basura y total sin relación', async () => {
  await assertFails(setDoc(doc(db('admin'), 'compras/bad'), { proveedorId: 'p1', proveedorNombre: 'Avícola Sur',
    lineas: [{ insumoId: 'noexiste', cantidad: -5, costoUnitario: 'x' }, 'texto', 42], estado: 'pendiente',
    creadoPor: 'admin', creadoPorNombre: 'Usuario admin', creadoEn: now() }));
});

audit('D2. proveedorNombre que no corresponde al proveedor', async () => {
  await assertFails(setDoc(doc(db('admin'), 'compras/bad2'), purchase('admin', { proveedorNombre: 'Otro proveedor falso' })));
});

audit('E. Entrada manual que además cambia el costo del insumo', async () => {
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 1, patch: { costoUnitario: 1 } }));
  await assertFails(adjust(db('admin'), 'admin', { tipo: 'entrada', delta: 1, patch: { costoUnitario: 1 } })); // ni el admin por este camino
});

audit('E2. Entrada manual sin motivo para inflar el stock', async () => {
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 900000, move: { motivo: '' } }));
  await assertFails(adjust(db('k'), 'k', { tipo: 'entrada', delta: 900000, move: { motivo: '   ' } }));
});

audit('G. Recibir la misma compra dos veces', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await assertSucceeds(receive(db('admin2'), 'admin2', { lines: [['i1', 1000, 10000, 100]] }));
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 1000, 11000, 100]] }));
});

audit('G2. Reutilizar los movimientos de una compra ya recibida en otro lote', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await receive(db('admin2'), 'admin2', { lines: [['i1', 1000, 10000, 100]] });
  const d = db('admin2'); const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/c1_extra'), movement('admin2', 'i1', 'compra', 1000, 12000, { motivo: '', compraId: 'c1', linea: 0 }));
  b.update(doc(d, 'insumos/i1'), { stock: 12000, ultimoMovimiento: 'c1_extra', actualizadoEn: now() });
  await assertFails(b.commit());
});

audit('H. Recepción legítima de una compra de 5 líneas (el máximo)', async () => {
  await seedSupplies(3);
  const ids = ['i1', 'i2', 'i3', 'i4', 'i5'];
  const stocks = { i1: 10000, i2: 5000 };
  await seedPurchase(ids.map((i) => line(i, 1000, 100)));
  await assertSucceeds(receive(db('admin2'), 'admin2', { lines: ids.map((i) => [i, 1000, stocks[i] ?? 1000, 100]) }));
});

audit('H2. Recibir una compra de una línea tocando 30 insumos ajenos', async () => {
  await seedSupplies(30);
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('admin2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'admin2', recibidoPorNombre: 'Usuario admin2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/c1_0'), movement('admin2', 'i1', 'compra', 1000, 11000, { motivo: '', compraId: 'c1', linea: 0 }));
  b.update(doc(d, 'insumos/i1'), { stock: 11000, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  b.set(doc(d, 'costosInsumos/i1'), { costoUnitario: 100, actualizadoEn: now(), actualizadoPor: 'admin2' });
  for (let i = 3; i < 33; i++) {
    b.set(doc(d, 'movimientosInventario', `k${i}`), movement('admin2', `i${i}`, 'compra', 1000, 2000, { motivo: '', compraId: 'c1', linea: 0 }));
    b.update(doc(d, 'insumos', `i${i}`), { stock: 2000, ultimoMovimiento: `k${i}`, actualizadoEn: now() });
  }
  await assertFails(b.commit());
});
