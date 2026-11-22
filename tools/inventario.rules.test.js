// Reglas de inventario, recetas, proveedores y compras (Fase 7), con las
// correcciones de la auditoría de seguridad (ver «Regresión de la auditoría»).
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
    await setDoc(doc(d, 'insumos/i1'), { nombre: 'Pollo', unidad: 'kg', stock: 10000, stockMinimo: 2000, costoUnitario: 1200,
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'insumos/i2'), { nombre: 'Papa', unidad: 'kg', stock: 5000, stockMinimo: 1000, costoUnitario: 300,
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    for (let i = 3; i < 3 + extra; i++) {
      await setDoc(doc(d, 'insumos', `i${i}`), { nombre: `i${i}`, unidad: 'kg', stock: 1000, stockMinimo: 0, costoUnitario: 100,
        activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    }
  });
}

async function seedBase() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ stock: 'almacen', stock2: 'almacen', stockoff: 'almacen', w1: 'mesero',
      cash: 'cajero', k: 'cocina', admin: 'admin', super: 'superadmin', inactive: 'almacen' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: uid !== 'inactive' });
    }
    for (const uid of ['stock', 'stock2', 'w1', 'cash', 'k', 'inactive']) {
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: true, asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'estadoAsistencia', 'stockoff'), { abierta: false, asistenciaId: 'astockoff' });
    await setDoc(doc(d, 'proveedores/p1'), { nombre: 'Avícola Sur', ruc: '20123456789', telefono: '999', contacto: 'Luis',
      activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'proveedores/p2'), { nombre: 'Inactivo SAC', ruc: '', telefono: '', contacto: '',
      activo: false, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'carta/d1'), { nombre: 'Pollo a la brasa', precio: 25, disponible: true });
  });
  await seedSupplies();
}
beforeEach(seedBase);

const newSupply = (extra = {}) => ({ nombre: 'Aceite', unidad: 'l', stock: 0, stockMinimo: 1000, costoUnitario: 800,
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
test('almacén, admin y superadmin crean insumos; el resto no', async () => {
  for (const uid of ['stock', 'admin', 'super']) await assertSucceeds(setDoc(doc(db(uid), 'insumos', `n-${uid}`), newSupply()));
  for (const uid of ['w1', 'cash', 'k', 'inactive', 'stockoff']) await assertFails(setDoc(doc(db(uid), 'insumos', 'x'), newSupply()));
  await assertFails(setDoc(doc(anon(), 'insumos', 'x'), newSupply()));
  await assertFails(setDoc(doc(db('stock', false), 'insumos', 'x'), newSupply()));
});

test('insumo nuevo inválido: stock inicial, unidad, valores y campos', async () => {
  for (const extra of [{ stock: 5 }, { unidad: 'caja' }, { nombre: 'a' }, { nombre: '  ' }, { stockMinimo: -1 }, { stockMinimo: 1.5 },
    { costoUnitario: -1 }, { costoUnitario: 'x' }, { activo: 'si' }, { creadoEn: Timestamp.now() }, { extra: 1 }]) {
    await assertFails(setDoc(doc(db('stock'), 'insumos', 'x'), newSupply(extra)));
  }
});

test('edición del catálogo: no toca el stock ni la unidad; el costo solo lo cambia la administración', async () => {
  await assertSucceeds(updateDoc(doc(db('stock'), 'insumos/i1'), { nombre: 'Pollo entero', stockMinimo: 3000, activo: false, actualizadoEn: now() }));
  await assertSucceeds(updateDoc(doc(db('stock'), 'insumos/i2'), { nombre: 'Papa', costoUnitario: 300, actualizadoEn: now() })); // mismo costo
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i2'), { costoUnitario: 1, actualizadoEn: now() })); // costo manipulado
  for (const uid of ['admin', 'super']) await assertSucceeds(updateDoc(doc(db(uid), 'insumos/i2'), { costoUnitario: 350, actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { stock: 99999, actualizadoEn: now() })); // sin movimiento
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { unidad: 'g', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { nombre: 'x', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { stockMinimo: -5, actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('w1'), 'insumos/i1'), { nombre: 'Hackeado', actualizadoEn: now() }));
  for (const uid of ['stock', 'admin', 'super']) await assertFails(deleteDoc(doc(db(uid), 'insumos/i1')));
});

test('lectura de inventario: almacén y administración; el resto no', async () => {
  for (const uid of ['stock', 'admin', 'super']) {
    for (const c of ['insumos', 'proveedores', 'compras', 'recetas', 'movimientosInventario']) {
      await assertSucceeds(getDocs(collection(db(uid), c)));
    }
  }
  for (const uid of ['w1', 'cash', 'inactive', 'stockoff']) {
    await assertFails(getDocs(collection(db(uid), 'insumos')));
    await assertFails(getDocs(collection(db(uid), 'recetas')));
  }
  // Cocina lee insumos y recetas (Fase 8B, para calcular el descuento), pero no el resto.
  await assertSucceeds(getDocs(collection(db('k'), 'insumos')));
  await assertSucceeds(getDocs(collection(db('k'), 'recetas')));
  for (const c of ['proveedores', 'compras', 'movimientosInventario']) await assertFails(getDocs(collection(db('k'), c)));
  await assertFails(getDocs(collection(anon(), 'insumos')));
});

// --------------------------------------------------------------- movimientos
test('entrada, salida, merma y ajuste dejan stock y movimiento consistentes', async () => {
  await assertSucceeds(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000 }));
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 12000);
  const m = (await getDoc(doc(f, 'movimientosInventario/m1'))).data();
  assert.equal(m.delta, 2000); assert.equal(m.creadoPor, 'stock'); assert.ok(m.creadoEn);
});

test('todo movimiento manual exige motivo, también la entrada, y respeta el signo', async () => {
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, move: { motivo: '' } }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, move: { motivo: 'ab' } }));
  await assertSucceeds(adjust(db('stock'), 'stock', { tipo: 'salida', delta: -3000 }));
  await assertFails(adjust(db('stock'), 'stock', { id: 'm2', tipo: 'salida', delta: 3000, before: 7000 })); // signo
  await assertFails(adjust(db('stock'), 'stock', { id: 'm2', tipo: 'entrada', delta: -3000, before: 7000 }));
  await assertFails(adjust(db('stock'), 'stock', { id: 'm2', tipo: 'merma', delta: 100, before: 7000 }));
  await assertFails(adjust(db('stock'), 'stock', { id: 'm2', tipo: 'merma', delta: -100, before: 7000, move: { motivo: '' } }));
  await assertFails(adjust(db('stock'), 'stock', { id: 'm2', tipo: 'ajuste', delta: -100, before: 7000, move: { motivo: 'ab' } }));
  await assertSucceeds(adjust(db('admin'), 'admin', { id: 'm3', tipo: 'ajuste', delta: -100, before: 7000 }));
});

test('el stock no puede quedar negativo ni inconsistente con el movimiento', async () => {
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'salida', delta: -10001 })); // negativo
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, result: 99999 })); // stock distinto
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, move: { stockResultante: 1 } }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 0 }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 1.5 }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, patch: { ultimoMovimiento: 'otro' } }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, patch: { nombre: 'x' } }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 2000, move: { insumoNombre: 'Falso' } }));
});

test('un movimiento sin cambio de stock, o un cambio de stock sin movimiento, se rechaza', async () => {
  const d = db('stock');
  await assertFails(setDoc(doc(d, 'movimientosInventario', 'solo'), movement('stock', 'i1', 'entrada', 2000, 12000)));
  const batch = writeBatch(d);
  batch.update(doc(d, 'insumos', 'i1'), { stock: 12000, ultimoMovimiento: 'fantasma', actualizadoEn: now() });
  await assertFails(batch.commit());
});

test('movimientos: identidad, hora, campos y roles; son de solo agregar', async () => {
  for (const move of [{ creadoPor: 'stock2' }, { creadoPorNombre: 'Falso' }, { creadoEn: Timestamp.now() }, { extra: 1 },
    { tipo: 'otro' }, { insumoId: 'i2' }, { motivo: 'x'.repeat(121) }, { compraId: 'c1' }, { linea: 0 }, { costoUnitario: 1 }]) {
    await assertFails(adjust(db('stock'), 'stock', { move }));
  }
  for (const uid of ['w1', 'cash', 'k', 'inactive', 'stockoff']) await assertFails(adjust(db(uid), uid));
  await assertSucceeds(adjust(db('stock'), 'stock'));
  for (const uid of ['stock', 'admin', 'super']) {
    await assertFails(updateDoc(doc(db(uid), 'movimientosInventario/m1'), { delta: 1 }));
    await assertFails(deleteDoc(doc(db(uid), 'movimientosInventario/m1')));
  }
});

test('un insumo desactivado no recibe movimientos', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { activo: false }));
  await assertFails(adjust(db('stock'), 'stock'));
});

// --------------------------------------------------------------- proveedores
const supplier = (extra = {}) => ({ nombre: 'Nuevo SAC', ruc: '20999999999', telefono: '987654321', contacto: 'Ana',
  activo: true, creadoEn: now(), actualizadoEn: now(), ...extra });

test('proveedores: alta, edición y desactivación; sin borrado', async () => {
  for (const uid of ['stock', 'admin', 'super']) await assertSucceeds(setDoc(doc(db(uid), 'proveedores', `n-${uid}`), supplier()));
  await assertSucceeds(setDoc(doc(db('stock'), 'proveedores', 'sinruc'), supplier({ ruc: '' })));
  for (const extra of [{ nombre: 'a' }, { ruc: '123' }, { ruc: 'abcdefghijk' }, { telefono: 'x'.repeat(21) }, { activo: 1 }, { extra: 1 }]) {
    await assertFails(setDoc(doc(db('stock'), 'proveedores', 'bad'), supplier(extra)));
  }
  await assertFails(setDoc(doc(db('w1'), 'proveedores', 'bad'), supplier()));
  await assertSucceeds(setDoc(doc(db('stock'), 'proveedores/p1'), supplier({ creadoEn: (await getDoc(doc(db('admin'), 'proveedores/p1'))).data().creadoEn, activo: false })));
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

test('compra: se crea pendiente, con proveedor activo y líneas válidas', async () => {
  for (const uid of ['stock', 'admin', 'super']) await assertSucceeds(setDoc(doc(db(uid), 'compras', `c-${uid}`), purchase(uid)));
  await assertSucceeds(setDoc(doc(db('stock'), 'compras', 'dos'), purchase('stock', { lineas: [line('i1'), line('i2', 2000, 350)] })));
  for (const uid of ['w1', 'cash', 'k', 'inactive', 'stockoff']) await assertFails(setDoc(doc(db(uid), 'compras', 'x'), purchase(uid)));
});

test('compra inválida a nivel de documento', async () => {
  for (const extra of [{ proveedorId: 'p2', proveedorNombre: 'Inactivo SAC' }, { proveedorId: 'nada' }, { lineas: [] }, { total: 5000 }, // el total no se guarda: se deriva de las líneas
   
    { estado: 'recibida' }, { creadoPor: 'stock2' }, { creadoPorNombre: 'Falso' }, { creadoEn: Timestamp.now() }, { extra: 1 },
    { proveedorNombre: 'Otro proveedor falso' }]) {
    await assertFails(setDoc(doc(db('stock'), 'compras', 'bad'), purchase('stock', extra)));
  }
});

test('cada línea se valida: insumo, cantidad, costo, subtotal y orden', async () => {
  const bad = (lineas) => assertFails(setDoc(doc(db('stock'), 'compras', 'bad'), purchase('stock', { lineas })));
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

// Por el límite de expresiones de las reglas (1000 por evaluación) el insumo de cada línea
// no se consulta al crear la compra: se exige al recibirla, cuando el movimiento lo valida.
test('una línea con insumo inexistente, desactivado o de otro insumo no se puede recibir', async () => {
  const cases = [[line('noexiste', 1000, 100), 'noexiste'], [line('i1', 1000, 100), 'i2']];
  for (const [l, id] of cases) {
    await seedBase();
    await seedPurchase([l]);
    await assertFails(receive(db('stock2'), 'stock2', { lines: [[id, 1000, 10000, 100]] }));
  }
  await seedBase();
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { activo: false }));
  await seedPurchase([line('i1', 1000, 100)]);
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i1', 1000, 10000, 100]] }));
});

test('una compra admite hasta 8 líneas', async () => {
  await seedSupplies(8);
  const ids = ['i1', 'i2', 'i3', 'i4', 'i5', 'i6', 'i7', 'i8'];
  await assertSucceeds(setDoc(doc(db('stock'), 'compras', 'ocho'), purchase('stock', { lineas: ids.map((i) => line(i, 1000, 100)) })));
  await assertFails(setDoc(doc(db('stock'), 'compras', 'nueve'), purchase('stock', { lineas: [...ids, 'i9'].map((i) => line(i, 1000, 100)) })));
});

async function seedPurchase(lines = [line('i1', 4000, 1250), line('i2', 2000, 350)], by = 'stock') {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'compras/c1'), { proveedorId: 'p1', proveedorNombre: 'Avícola Sur',
    lineas: lines, estado: 'pendiente', creadoPor: by, creadoPorNombre: `Usuario ${by}`, creadoEn: Timestamp.now() }));
}
// Recibe la compra c1: su cambio de estado + un movimiento (c1_n) y el stock de cada línea.
function receive(database, uid, { compra = 'c1', lines = [['i1', 4000, 10000, 1250], ['i2', 2000, 5000, 350]], skipPurchase = false,
  purchasePatch = {}, move = {}, supplyPatch = {} } = {}) {
  const batch = writeBatch(database);
  if (!skipPurchase) {
    batch.update(doc(database, 'compras', compra), { estado: 'recibida', recibidoPor: uid, recibidoPorNombre: `Usuario ${uid}`, recibidoEn: now(), ...purchasePatch });
  }
  lines.forEach(([id, qty, before, cost], n) => {
    const mid = `${compra}_${n}`;
    batch.set(doc(database, 'movimientosInventario', mid), movement(uid, id, 'compra', qty, before + qty,
      { motivo: '', compraId: compra, linea: n, costoUnitario: cost, ...move }));
    batch.update(doc(database, 'insumos', id), { stock: before + qty, costoUnitario: cost, ultimoMovimiento: mid, actualizadoEn: now(), ...supplyPatch });
  });
  return batch.commit();
}

test('recibir una compra la cierra y suma stock y costo de cada línea, en un solo lote', async () => {
  await seedPurchase();
  await assertSucceeds(receive(db('stock2'), 'stock2'));
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'compras/c1'))).data().estado, 'recibida');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 14000);
  assert.equal((await getDoc(doc(f, 'insumos/i2'))).data().stock, 7000);
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().costoUnitario, 1250);
  assert.equal((await getDoc(doc(f, 'movimientosInventario/c1_1'))).data().linea, 1);
});

test('separación de funciones: quien crea la compra no la recibe; Admin y Superadmin sí', async () => {
  await seedPurchase();
  await assertFails(receive(db('stock'), 'stock')); // creador, almacén
  await assertSucceeds(receive(db('stock2'), 'stock2'));
  for (const uid of ['admin', 'super']) {
    // la compra la crea el propio Admin/Superadmin
    await seedBase();
    await seedPurchase([line('i1', 4000, 1250)], uid);
    await assertSucceeds(receive(db(uid), uid, { lines: [['i1', 4000, 10000, 1250]] }));
  }
});

test('recibir exige el movimiento de cada línea, con cantidad, insumo y costo de la línea', async () => {
  await seedPurchase();
  await assertFails(receive(db('stock2'), 'stock2', { lines: [] })); // sin movimientos
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i1', 4000, 10000, 1250]] })); // falta la línea 2
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i1', 4000, 10000, 1250], ['i2', 2001, 5000, 350]] })); // cantidad distinta
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i1', 4000, 10000, 1], ['i2', 2000, 5000, 350]] })); // costo distinto
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i2', 2000, 5000, 350], ['i1', 4000, 10000, 1250]] })); // insumos cruzados
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'compras/c1'))).data().estado, 'pendiente');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 10000);
});

test('recibir: costo del insumo, stock resultante y movimiento deben coincidir con la línea', async () => {
  await seedPurchase([line('i1', 4000, 1250)]);
  const one = [['i1', 4000, 10000, 1250]];
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, supplyPatch: { costoUnitario: 1 } })); // costo del insumo ≠ línea
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, move: { stockResultante: 1 } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, move: { tipo: 'entrada' } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, move: { motivo: 'algo' } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, move: { linea: 1 } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, move: { compraId: 'otra' } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, purchasePatch: { recibidoPor: 'stock' } }));
  await assertFails(receive(db('stock2'), 'stock2', { lines: one, purchasePatch: { total: 1 } }));
  await assertFails(receive(db('w1'), 'w1', { lines: one }));
  await assertSucceeds(receive(db('stock2'), 'stock2', { lines: one }));
});

test('una compra no se recibe dos veces ni después de cancelada', async () => {
  await seedPurchase();
  await assertSucceeds(receive(db('stock2'), 'stock2'));
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 4000, 14000, 1250], ['i2', 2000, 7000, 350]] }));
  await seedPurchase();
  const cancel = (extra = {}) => updateDoc(doc(db('stock'), 'compras/c1'), { estado: 'cancelada', canceladoPor: 'stock',
    canceladoPorNombre: 'Usuario stock', canceladoEn: now(), motivoCancelacion: 'Proveedor sin stock', ...extra });
  await assertFails(cancel({ motivoCancelacion: 'ab' }));
  await assertFails(cancel({ canceladoPor: 'admin' }));
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'compras/c1'), { estado: 'pendiente' }));
  await assertSucceeds(cancel());
  await assertFails(receive(db('stock2'), 'stock2'));
  await assertFails(updateDoc(doc(db('admin'), 'compras/c1'), { estado: 'pendiente' }));
  await assertFails(deleteDoc(doc(db('admin'), 'compras/c1')));
});

// ------------------------------------------------------------------- recetas
test('recetas: almacén y administración, de un plato existente, con ingredientes bien formados', async () => {
  const ing = (extra = {}) => ({ insumoId: 'i1', nombre: 'Pollo', cantidad: 500, ...extra });
  const recipe = (uid, extra = {}) => ({ ingredientes: [ing()], actualizadoPor: uid, actualizadoEn: now(), ...extra });
  for (const uid of ['stock', 'admin', 'super']) await assertSucceeds(setDoc(doc(db(uid), 'recetas/d1'), recipe(uid)));
  await assertSucceeds(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock', { ingredientes: [] })));
  await assertFails(setDoc(doc(db('stock'), 'recetas/inexistente'), recipe('stock')));
  await assertFails(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock2')));
  await assertFails(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock', { actualizadoEn: Timestamp.now() })));
  await assertFails(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock', { ingredientes: Array.from({ length: 31 }, () => ing()) })));
  await assertFails(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock', { extra: 1 })));
  for (const bad of [['texto'], [ing({ cantidad: -1 })], [ing({ cantidad: 0 })], [ing({ cantidad: 1.5 })], [ing({ cantidad: 'x' })], [ing({ extra: 1 })], [{ insumoId: 'i1' }], 42]) {
    await assertFails(setDoc(doc(db('stock'), 'recetas/d1'), recipe('stock', { ingredientes: bad })));
  }
  for (const uid of ['w1', 'cash', 'k', 'inactive', 'stockoff']) await assertFails(setDoc(doc(db(uid), 'recetas/d1'), recipe(uid)));
  await assertFails(deleteDoc(doc(db('admin'), 'recetas/d1')));
});

test('sin jornada abierta el almacén pierde el inventario; el admin no', async () => {
  await assertFails(adjust(db('stockoff'), 'stockoff'));
  await assertFails(getDocs(collection(db('stockoff'), 'insumos')));
  await assertSucceeds(adjust(db('admin'), 'admin'));
});

// =============================================================================
// Regresión de la auditoría de seguridad (2026-11-19): los 17 intentos de
// manipulación del sondeo, que antes se permitían (A–F, H2) o ya estaban
// bloqueados (G, G2) o eran legítimos (H).
// =============================================================================
const audit = test;

audit('A. Reescribir el stock apuntando a un movimiento histórico, sin movimiento nuevo', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'movimientosInventario/old'), { insumoId: 'i1', insumoNombre: 'Pollo',
    tipo: 'entrada', delta: 1, stockResultante: 50000, motivo: 'viejo', creadoPor: 'stock', creadoPorNombre: 'Usuario stock', creadoEn: old() }));
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { stock: 50000, ultimoMovimiento: 'old', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('admin'), 'insumos/i1'), { stock: 50000, ultimoMovimiento: 'old', actualizadoEn: now() }));
});

audit('A2. Lo mismo bajando el stock a 0 con un movimiento histórico', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'movimientosInventario/zero'), { insumoId: 'i1', insumoNombre: 'Pollo',
    tipo: 'salida', delta: -1, stockResultante: 0, motivo: 'viejo', creadoPor: 'stock', creadoPorNombre: 'x', creadoEn: old() }));
  await assertFails(updateDoc(doc(db('stock'), 'insumos/i1'), { stock: 0, ultimoMovimiento: 'zero', actualizadoEn: now() }));
});

audit('A3. Un movimiento nuevo no sirve para otro insumo ni para dos insumos a la vez', async () => {
  const d = db('stock'); const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/n1'), movement('stock', 'i1', 'entrada', 2000, 12000));
  b.update(doc(d, 'insumos/i1'), { stock: 12000, ultimoMovimiento: 'n1', actualizadoEn: now() });
  b.update(doc(d, 'insumos/i2'), { stock: 7000, ultimoMovimiento: 'n1', actualizadoEn: now() }); // reutiliza el mismo movimiento
  await assertFails(b.commit());
});

audit('B. Recibir una compra de una línea y sumar stock a un insumo que no está en ella', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('stock2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/x1'), movement('stock2', 'i2', 'compra', 900000, 905000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 300 }));
  b.update(doc(d, 'insumos/i2'), { stock: 905000, costoUnitario: 300, ultimoMovimiento: 'x1', actualizadoEn: now() });
  await assertFails(b.commit());
  // con el id correcto de la línea pero del insumo equivocado
  const b2 = writeBatch(d);
  b2.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() });
  b2.set(doc(d, 'movimientosInventario/c1_0'), movement('stock2', 'i2', 'compra', 1000, 6000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
  b2.update(doc(d, 'insumos/i2'), { stock: 6000, costoUnitario: 100, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  await assertFails(b2.commit());
});

audit('B2. Un movimiento «compra» que en realidad baja el stock con un resultante falso', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  for (const [delta, result] of [[1, 0], [1000, 0], [1000, 12000]]) {
    const d = db('stock2'); const b = writeBatch(d);
    b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() });
    b.set(doc(d, 'movimientosInventario/c1_0'), movement('stock2', 'i1', 'compra', delta, result, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
    b.update(doc(d, 'insumos/i1'), { stock: result, costoUnitario: 100, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
    await assertFails(b.commit());
  }
});

audit('B3. Sumar una cantidad distinta de la comprada', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await assertFails(receive(db('stock2'), 'stock2', { lines: [['i1', 500000, 10000, 100]] }));
  await assertSucceeds(receive(db('stock2'), 'stock2', { lines: [['i1', 1000, 10000, 100]] }));
});

audit('B4. Fijar costos de insumos sin relación con la compra', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('stock2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/c1_0'), movement('stock2', 'i1', 'compra', 1000, 11000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
  b.update(doc(d, 'insumos/i1'), { stock: 11000, costoUnitario: 1, ultimoMovimiento: 'c1_0', actualizadoEn: now() }); // costo ≠ línea
  b.set(doc(d, 'movimientosInventario/x2'), movement('stock2', 'i2', 'compra', 1, 5001, { motivo: '', compraId: 'c1', linea: 1, costoUnitario: 300 }));
  b.update(doc(d, 'insumos/i2'), { stock: 5001, costoUnitario: 9999900, ultimoMovimiento: 'x2', actualizadoEn: now() });
  await assertFails(b.commit());
});

audit('C. Recibir la compra sin ningún movimiento', async () => {
  await seedPurchase();
  await assertFails(updateDoc(doc(db('stock2'), 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() }));
});

audit('D. Compra con líneas basura y total sin relación', async () => {
  await assertFails(setDoc(doc(db('stock'), 'compras/bad'), { proveedorId: 'p1', proveedorNombre: 'Avícola Sur',
    lineas: [{ insumoId: 'noexiste', cantidad: -5, costoUnitario: 'x' }, 'texto', 42], estado: 'pendiente',
    creadoPor: 'stock', creadoPorNombre: 'Usuario stock', creadoEn: now() }));
});

audit('D2. proveedorNombre que no corresponde al proveedor', async () => {
  await assertFails(setDoc(doc(db('stock'), 'compras/bad2'), purchase('stock', { proveedorNombre: 'Otro proveedor falso' })));
});

audit('E. Entrada manual que además cambia el costo del insumo', async () => {
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 1, patch: { costoUnitario: 1 } }));
  await assertFails(adjust(db('admin'), 'admin', { tipo: 'entrada', delta: 1, patch: { costoUnitario: 1 } })); // ni el admin por este camino
});

audit('E2. Entrada manual sin motivo para inflar el stock', async () => {
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 900000, move: { motivo: '' } }));
  await assertFails(adjust(db('stock'), 'stock', { tipo: 'entrada', delta: 900000, move: { motivo: '   ' } }));
});

audit('F. Recepción por otro usuario: ahora solo si no es quien creó la compra', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await assertFails(receive(db('stock'), 'stock', { lines: [['i1', 1000, 10000, 100]] }));
  await assertSucceeds(receive(db('stock2'), 'stock2', { lines: [['i1', 1000, 10000, 100]] }));
});

audit('G. Recibir la misma compra dos veces', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await assertSucceeds(receive(db('stock2'), 'stock2', { lines: [['i1', 1000, 10000, 100]] }));
  await assertFails(receive(db('admin'), 'admin', { lines: [['i1', 1000, 11000, 100]] }));
});

audit('G2. Reutilizar los movimientos de una compra ya recibida en otro lote', async () => {
  await seedPurchase([line('i1', 1000, 100)]);
  await receive(db('stock2'), 'stock2', { lines: [['i1', 1000, 10000, 100]] });
  const d = db('stock2'); const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/c1_extra'), movement('stock2', 'i1', 'compra', 1000, 12000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
  b.update(doc(d, 'insumos/i1'), { stock: 12000, costoUnitario: 100, ultimoMovimiento: 'c1_extra', actualizadoEn: now() });
  await assertFails(b.commit());
});

audit('H. Recepción legítima de una compra de 8 líneas', async () => {
  await seedSupplies(8);
  const ids = ['i1', 'i2', 'i3', 'i4', 'i5', 'i6', 'i7', 'i8'];
  const stocks = { i1: 10000, i2: 5000 };
  await seedPurchase(ids.map((i) => line(i, 1000, 100)));
  await assertSucceeds(receive(db('stock2'), 'stock2', { lines: ids.map((i) => [i, 1000, stocks[i] ?? 1000, 100]) }));
});

audit('H2. Recibir una compra de una línea tocando 30 insumos ajenos', async () => {
  await seedSupplies(30);
  await seedPurchase([line('i1', 1000, 100)]);
  const d = db('stock2'); const b = writeBatch(d);
  b.update(doc(d, 'compras/c1'), { estado: 'recibida', recibidoPor: 'stock2', recibidoPorNombre: 'Usuario stock2', recibidoEn: now() });
  b.set(doc(d, 'movimientosInventario/c1_0'), movement('stock2', 'i1', 'compra', 1000, 11000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
  b.update(doc(d, 'insumos/i1'), { stock: 11000, costoUnitario: 100, ultimoMovimiento: 'c1_0', actualizadoEn: now() });
  for (let i = 3; i < 33; i++) {
    b.set(doc(d, 'movimientosInventario', `k${i}`), movement('stock2', `i${i}`, 'compra', 1000, 2000, { motivo: '', compraId: 'c1', linea: 0, costoUnitario: 100 }));
    b.update(doc(d, 'insumos', `i${i}`), { stock: 2000, costoUnitario: 100, ultimoMovimiento: `k${i}`, actualizadoEn: now() });
  }
  await assertFails(b.commit());
});
