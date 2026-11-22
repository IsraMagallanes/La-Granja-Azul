// Reglas de Caja y ventas (Fase 6). Se ejecuta contra el emulador de Firestore.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, deleteField } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-caja', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });

const db = (uid, verified = true) => env.authenticatedContext(uid, { email_verified: verified }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const now = () => serverTimestamp();

function order(mesa, extra = {}) {
  return { mesaId: mesa, meseroId: 'w1', meseroNombre: 'Usuario w1', estado: 'registrado', estadoCocina: 'entregado',
    revision: 5, cantidadDetalles: 1, detalleModificado: 'pollo', creadoEn: Timestamp.now(), registradoEn: Timestamp.now(),
    actualizadoEn: Timestamp.now(), ...extra };
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ w1: 'mesero', cash: 'cajero', cash2: 'cajero', cashoff: 'cajero', k: 'cocina',
      stock: 'almacen', admin: 'admin', super: 'superadmin', inactive: 'cajero' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: uid !== 'inactive' });
    }
    for (const uid of ['w1', 'cash', 'cash2', 'k', 'inactive']) {
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: true, asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'estadoAsistencia', 'cashoff'), { abierta: false, asistenciaId: 'acashoff' });
    await setDoc(doc(d, 'mesas/1'), { numero: '1', capacidad: 4, activo: true, pedidoActivo: 'a' });
    await setDoc(doc(d, 'mesas/2'), { numero: '2', capacidad: 4, activo: true, pedidoActivo: 'b' });
    await setDoc(doc(d, 'mesas/3'), { numero: '3', capacidad: 4, activo: true, pedidoActivo: 'c' });
    await setDoc(doc(d, 'mesas/4'), { numero: '4', capacidad: 4, activo: true, pedidoActivo: 'd' });
    await setDoc(doc(d, 'pedidos/a'), order('1'));
    await setDoc(doc(d, 'pedidos/b'), order('2', { estadoCocina: 'listo' }));
    await setDoc(doc(d, 'pedidos/c'), withoutKitchen(order('3'), 'abierto'));
    await setDoc(doc(d, 'pedidos/d'), order('4'));
  });
});

function withoutKitchen(o, estado) {
  const { estadoCocina, registradoEn, ...rest } = o;
  return { ...rest, estado };
}

// ---- ayudantes: abrir, cobrar, cerrar
function openBox(database, id, uid, extra = {}, lock = {}) {
  const batch = writeBatch(database);
  batch.set(doc(database, 'cajas', id), { estado: 'abierta', montoInicial: 10000, abiertaPor: uid,
    abiertaPorNombre: `Usuario ${uid}`, abiertaEn: now(), ...extra });
  batch.set(doc(database, 'cajaActiva', 'actual'), { cajaId: id, montoInicial: 10000, abiertaPor: uid,
    abiertaPorNombre: `Usuario ${uid}`, abiertaEn: now(), ...lock });
  return batch.commit();
}
function payment(uid, orderId, mesa, extra = {}) {
  return { pedidoId: orderId, mesaId: mesa, cajaId: 'c1', total: 5100, metodo: 'efectivo', recibido: 6000, vuelto: 900,
    cobradoPor: uid, cobradoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...extra };
}
function charge(database, uid, orderId = 'a', mesa = '1', { pay = {}, order: orderPatch = {}, release = true, skipPay = false, skipOrder = false } = {}) {
  const batch = writeBatch(database);
  if (!skipPay) batch.set(doc(database, 'pagos', orderId), payment(uid, orderId, mesa, pay));
  if (!skipOrder) batch.update(doc(database, 'pedidos', orderId), { estado: 'pagado', revision: 6, actualizadoEn: now(), ...orderPatch });
  if (release) batch.update(doc(database, 'mesas', mesa), { pedidoActivo: null });
  return batch.commit();
}
function closeFields(uid, extra = {}) {
  return { estado: 'cerrada', cerradaPor: uid, cerradaPorNombre: `Usuario ${uid}`, cerradaEn: now(), esperadoEfectivo: 15100,
    montoContado: 15100, diferencia: 0, ventasEfectivo: 5100, ventasOtros: 0, ingresos: 0, egresos: 0, cantidadVentas: 1,
    notasCierre: '', ...extra };
}
function closeBox(database, id, uid, extra = {}, { removeLock = true } = {}) {
  const batch = writeBatch(database);
  batch.update(doc(database, 'cajas', id), closeFields(uid, extra));
  if (removeLock) batch.delete(doc(database, 'cajaActiva', 'actual'));
  return batch.commit();
}
async function openAs(uid = 'cash') { await openBox(db(uid), 'c1', uid); }

// ------------------------------------------------------------------ apertura
test('cajero, admin y superadmin abren la caja; solo una a la vez', async () => {
  await assertSucceeds(openBox(db('cash'), 'c1', 'cash'));
  for (const uid of ['cash2', 'admin', 'super']) await assertFails(openBox(db(uid), 'c2', uid));
});

test('mesero, cocina, almacén, anónimo, inactivo, sin jornada o sin correo verificado no abren caja', async () => {
  for (const uid of ['w1', 'k', 'stock', 'inactive', 'cashoff']) await assertFails(openBox(db(uid), 'c1', uid));
  await assertFails(openBox(anon(), 'c1', 'cash'));
  await assertFails(openBox(db('cash', false), 'c1', 'cash'));
  await assertSucceeds(openBox(db('admin'), 'c1', 'admin')); // el admin está exento de la jornada
});

test('apertura inválida: monto, identidad, candado ajeno o sin candado', async () => {
  for (const extra of [{ montoInicial: -1 }, { montoInicial: 1.5 }, { montoInicial: 10000001 }, { abiertaPor: 'cash2' },
    { abiertaPorNombre: 'Falso' }, { abiertaEn: Timestamp.now() }, { estado: 'cerrada' }, { extra: 1 }]) {
    await assertFails(openBox(db('cash'), 'c1', 'cash', extra));
  }
  await assertFails(openBox(db('cash'), 'c1', 'cash', {}, { cajaId: 'otra' }));
  await assertFails(openBox(db('cash'), 'c1', 'cash', {}, { montoInicial: 99 }));
  await assertFails(setDoc(doc(db('cash'), 'cajas', 'c1'), { estado: 'abierta', montoInicial: 0, abiertaPor: 'cash',
    abiertaPorNombre: 'Usuario cash', abiertaEn: now() })); // sin candado
  await assertFails(setDoc(doc(db('cash'), 'cajaActiva', 'actual'), { cajaId: 'c1', montoInicial: 10000, abiertaPor: 'cash',
    abiertaPorNombre: 'Usuario cash', abiertaEn: now() })); // candado sin caja
});

// --------------------------------------------------------------------- cobro
test('cobro en efectivo con vuelto: pago, pedido pagado y mesa libre en un solo lote', async () => {
  await openAs();
  await assertSucceeds(charge(db('cash'), 'cash'));
  const f = db('admin');
  const p = (await getDoc(doc(f, 'pagos/a'))).data();
  assert.equal(p.total, 5100); assert.equal(p.vuelto, 900); assert.equal(p.cobradoPor, 'cash'); assert.ok(p.creadoEn);
  assert.equal((await getDoc(doc(f, 'pedidos/a'))).data().estado, 'pagado');
  assert.equal((await getDoc(doc(f, 'mesas/1'))).data().pedidoActivo, null);
});

test('tarjeta, Yape y Plin cobran el total exacto; el efectivo no puede ser menor', async () => {
  await openAs();
  await assertSucceeds(charge(db('cash'), 'cash', 'a', '1', { pay: { metodo: 'tarjeta', recibido: 5100, vuelto: 0 } }));
  await assertSucceeds(charge(db('cash'), 'cash', 'd', '4', { pay: { metodo: 'yape', recibido: 5100, vuelto: 0 } }));
  for (const pay of [{ metodo: 'efectivo', recibido: 5000, vuelto: 0 }, { metodo: 'efectivo', recibido: 6000, vuelto: 0 },
    { metodo: 'efectivo', recibido: 6000, vuelto: 1000 }, { metodo: 'tarjeta', recibido: 6000, vuelto: 900 },
    { metodo: 'plin', recibido: 5000, vuelto: 0 }, { metodo: 'cheque', recibido: 5100, vuelto: 0 },
    { total: 0 }, { total: -5 }, { total: 5.5 }, { total: 10000001 }]) {
    await assertFails(charge(db('cash'), 'cash', 'b', '2', { pay }));
  }
});

test('un pedido no se cobra dos veces', async () => {
  await openAs();
  await assertSucceeds(charge(db('cash'), 'cash'));
  await assertFails(charge(db('cash'), 'cash')); // mismo cajero
  await assertFails(charge(db('cash2'), 'cash2')); // otro cajero
  await assertFails(charge(db('admin'), 'admin'));
  await assertFails(setDoc(doc(db('admin'), 'pagos', 'a'), payment('admin', 'a', '1')));
});

test('dos cajeros cobrando el mismo pedido a la vez: solo uno lo logra', async () => {
  await openAs();
  const results = await Promise.allSettled([charge(db('cash'), 'cash'), charge(db('cash2'), 'cash2')]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const payments = await getDocs(collection(db('admin'), 'pagos'));
  assert.equal(payments.size, 1);
});

test('un cobro incompleto o inconsistente no libera la mesa ni cierra el pedido', async () => {
  await openAs();
  const broken = [
    () => charge(db('cash'), 'cash', 'a', '1', { release: false }), // sin liberar la mesa
    () => charge(db('cash'), 'cash', 'a', '1', { skipPay: true }), // sin pago
    () => charge(db('cash'), 'cash', 'a', '1', { skipOrder: true }), // sin cerrar el pedido
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { cajaId: 'otra' } }), // caja que no es la abierta
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { cobradoPor: 'cash2' } }), // suplantación
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { cobradoPorNombre: 'Falso' } }),
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { creadoEn: Timestamp.now() } }), // hora falsa
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { pedidoId: 'b' } }), // pago de otro pedido
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { mesaId: '2' } }), // mesa que no corresponde
    () => charge(db('cash'), 'cash', 'a', '1', { pay: { extra: true } }),
    () => charge(db('cash'), 'cash', 'a', '1', { order: { estado: 'cancelado' } }),
    () => charge(db('cash'), 'cash', 'a', '1', { order: { revision: 9 } }),
    () => charge(db('cash'), 'cash', 'a', '1', { order: { meseroId: 'cash' } }),
    () => charge(db('cash'), 'cash', 'a', '1', { order: { estadoCocina: 'listo' } }),
  ];
  for (const attempt of broken) await assertFails(attempt());
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'pedidos/a'))).data().estado, 'registrado');
  assert.equal((await getDoc(doc(f, 'mesas/1'))).data().pedidoActivo, 'a');
  assert.equal((await getDocs(collection(f, 'pagos'))).size, 0);
});

test('la mesa no se libera por separado ni con el pedido sin pagar', async () => {
  await openAs();
  for (const uid of ['cash', 'admin', 'super', 'w1']) {
    await assertFails(updateDoc(doc(db(uid), 'mesas/1'), { pedidoActivo: null }));
  }
  const cash = db('cash');
  const batch = writeBatch(cash);
  batch.set(doc(cash, 'pagos', 'a'), payment('cash', 'a', '1'));
  batch.update(doc(cash, 'mesas/1'), { pedidoActivo: null }); // pago sin pasar el pedido a pagado
  await assertFails(batch.commit());
});

test('solo se cobra un pedido registrado y entregado por cocina', async () => {
  await openAs();
  await assertFails(charge(db('cash'), 'cash', 'b', '2')); // cocina: listo, aún no entregado
  await assertFails(charge(db('cash'), 'cash', 'c', '3')); // abierto
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'pedidos/d'), { estado: 'cancelado', estadoCocina: deleteField(), registradoEn: deleteField() }));
  await assertFails(charge(db('cash'), 'cash', 'd', '4'));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'pedidos/old'), (({ estadoCocina, ...rest }) => rest)(order('1'))); // registrado antes de la Fase 5
    await setDoc(doc(ctx.firestore(), 'mesas/1'), { numero: '1', capacidad: 4, activo: true, pedidoActivo: 'old' });
  });
  await assertFails(charge(db('cash'), 'cash', 'old', '1'));
});

test('sin caja abierta no se cobra', async () => {
  await assertFails(charge(db('cash'), 'cash'));
  await openAs();
  await assertSucceeds(closeBox(db('cash'), 'c1', 'cash'));
  await assertFails(charge(db('cash'), 'cash'));
});

test('quién puede cobrar: cajero, admin y superadmin; el resto no', async () => {
  await openAs();
  for (const uid of ['w1', 'k', 'stock', 'inactive', 'cashoff']) await assertFails(charge(db(uid), uid));
  await assertFails(charge(anon(), 'cash'));
  await assertFails(charge(db('cash', false), 'cash'));
  await assertSucceeds(charge(db('admin'), 'admin', 'a', '1'));
  await assertSucceeds(charge(db('super'), 'super', 'd', '4'));
});

test('el cajero sin jornada abierta pierde la caja; el admin no', async () => {
  await openAs();
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'estadoAsistencia/cash'), { abierta: false }));
  await assertFails(charge(db('cash'), 'cash'));
  await assertFails(getDoc(doc(db('cash'), 'cajaActiva/actual')));
  await assertSucceeds(charge(db('admin'), 'admin'));
});

test('lo cobrado es inmutable: pagos, pedido pagado y mesa', async () => {
  await openAs();
  await charge(db('cash'), 'cash');
  for (const uid of ['cash', 'admin', 'super']) {
    await assertFails(updateDoc(doc(db(uid), 'pagos/a'), { total: 1 }));
    await assertFails(deleteDoc(doc(db(uid), 'pagos/a')));
    await assertFails(updateDoc(doc(db(uid), 'pedidos/a'), { estado: 'registrado', revision: 7, actualizadoEn: now() }));
    await assertFails(updateDoc(doc(db(uid), 'pedidos/a'), { estado: 'cancelado', revision: 7, actualizadoEn: now(),
      motivoCancelacion: 'abc def', canceladoPor: uid }));
    await assertFails(deleteDoc(doc(db(uid), 'pedidos/a')));
  }
  await assertFails(updateDoc(doc(db('k'), 'pedidos/a'), { estadoCocina: 'listo', revision: 7, actualizadoEn: now() }));
});

test('lectura de pagos y cajas: personal de caja y administración; el resto no', async () => {
  await openAs();
  await charge(db('cash'), 'cash');
  for (const uid of ['cash', 'cash2', 'admin', 'super']) {
    await assertSucceeds(getDocs(collection(db(uid), 'pagos')));
    await assertSucceeds(getDocs(collection(db(uid), 'cajas')));
    await assertSucceeds(getDoc(doc(db(uid), 'cajaActiva/actual')));
    await assertSucceeds(getDocs(collection(db(uid), 'movimientosCaja')));
  }
  for (const uid of ['w1', 'k', 'stock', 'inactive', 'cashoff']) {
    await assertFails(getDocs(collection(db(uid), 'pagos')));
    await assertFails(getDocs(collection(db(uid), 'cajas')));
  }
  await assertFails(getDocs(collection(anon(), 'pagos')));
});

// ---------------------------------------------------------------- movimientos
const movement = (uid, extra = {}) => ({ cajaId: 'c1', tipo: 'egreso', monto: 2000, concepto: 'Compra de hielo', creadoPor: uid,
  creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...extra });

test('ingresos y egresos: solo con caja abierta, válidos y de solo agregar', async () => {
  await assertFails(setDoc(doc(db('cash'), 'movimientosCaja', 'm0'), movement('cash'))); // sin caja
  await openAs();
  await assertSucceeds(setDoc(doc(db('cash'), 'movimientosCaja', 'm1'), movement('cash')));
  await assertSucceeds(setDoc(doc(db('admin'), 'movimientosCaja', 'm2'), movement('admin', { tipo: 'ingreso', concepto: 'Sencillo' })));
  for (const extra of [{ monto: 0 }, { monto: -5 }, { monto: 1.5 }, { monto: 10000001 }, { tipo: 'otro' }, { concepto: 'ab' },
    { concepto: 'x'.repeat(121) }, { cajaId: 'otra' }, { creadoPor: 'cash2' }, { creadoPorNombre: 'Falso' },
    { creadoEn: Timestamp.now() }, { extra: 1 }]) {
    await assertFails(setDoc(doc(db('cash'), 'movimientosCaja', 'mx'), movement('cash', extra)));
  }
  for (const uid of ['w1', 'k', 'stock', 'inactive']) await assertFails(setDoc(doc(db(uid), 'movimientosCaja', 'my'), movement(uid)));
  await assertFails(updateDoc(doc(db('admin'), 'movimientosCaja/m1'), { monto: 1 }));
  await assertFails(deleteDoc(doc(db('admin'), 'movimientosCaja/m1')));
});

// --------------------------------------------------------------------- cierre
test('cierre cuadrado: cierra la caja y quita el candado en el mismo lote', async () => {
  await openAs();
  await charge(db('cash'), 'cash');
  await assertSucceeds(closeBox(db('cash'), 'c1', 'cash'));
  const f = db('admin');
  const c = (await getDoc(doc(f, 'cajas/c1'))).data();
  assert.equal(c.estado, 'cerrada'); assert.equal(c.cerradaPor, 'cash'); assert.equal(c.diferencia, 0);
  assert.equal((await getDoc(doc(f, 'cajaActiva/actual'))).exists(), false);
  await assertSucceeds(openBox(db('cash2'), 'c2', 'cash2')); // ya se puede abrir otra
});

test('con diferencia, el cierre exige una nota y la diferencia debe ser exacta', async () => {
  await openAs();
  await assertFails(closeBox(db('cash'), 'c1', 'cash', { montoContado: 15000, diferencia: -100 })); // sin nota
  await assertFails(closeBox(db('cash'), 'c1', 'cash', { montoContado: 15000, diferencia: -100, notasCierre: 'ab' }));
  await assertFails(closeBox(db('cash'), 'c1', 'cash', { montoContado: 15000, diferencia: 0 })); // diferencia falsa
  await assertFails(closeBox(db('cash'), 'c1', 'cash', { montoContado: 15000, diferencia: -50, notasCierre: 'Faltan 50' }));
  await assertSucceeds(closeBox(db('cash'), 'c1', 'cash', { montoContado: 15000, diferencia: -100, notasCierre: 'Faltan S/ 1.00' }));
  assert.equal((await getDoc(doc(db('admin'), 'cajas/c1'))).data().diferencia, -100);
});

test('cierre inválido: montos, identidad, hora y candado', async () => {
  await openAs();
  for (const extra of [{ montoContado: -1, diferencia: -15101 }, { montoContado: 1.5, diferencia: -15099.5 },
    { esperadoEfectivo: 'x' }, { ventasEfectivo: -1 }, { cantidadDetalles: 1 }, { cerradaPor: 'cash2' },
    { cerradaPorNombre: 'Falso' }, { cerradaEn: Timestamp.now() }, { notasCierre: 'x'.repeat(201) }, { montoInicial: 0 },
    { abiertaPor: 'cash2' }, { estado: 'abierta' }]) {
    await assertFails(closeBox(db('cash'), 'c1', 'cash', extra));
  }
  await assertFails(closeBox(db('cash'), 'c1', 'cash', {}, { removeLock: false })); // cerrar sin quitar el candado
  await assertFails(deleteDoc(doc(db('cash'), 'cajaActiva/actual'))); // quitar el candado sin cerrar
  await assertFails(updateDoc(doc(db('cash'), 'cajaActiva/actual'), { montoInicial: 1 }));
});

test('solo quien abrió la caja o un administrador la cierra', async () => {
  await openAs('cash');
  await assertFails(closeBox(db('cash2'), 'c1', 'cash2'));
  for (const uid of ['w1', 'k', 'stock', 'inactive']) await assertFails(closeBox(db(uid), 'c1', uid));
  await assertSucceeds(closeBox(db('admin'), 'c1', 'admin'));
});

test('una caja cerrada no se puede cambiar ni borrar', async () => {
  await openAs();
  await closeBox(db('cash'), 'c1', 'cash');
  for (const uid of ['cash', 'admin', 'super']) {
    await assertFails(updateDoc(doc(db(uid), 'cajas/c1'), { montoContado: 1, diferencia: -15100, notasCierre: 'cambio' }));
    await assertFails(updateDoc(doc(db(uid), 'cajas/c1'), { estado: 'abierta' }));
    await assertFails(deleteDoc(doc(db(uid), 'cajas/c1')));
  }
});
