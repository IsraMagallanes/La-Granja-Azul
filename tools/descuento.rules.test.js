// Fase 8B: descuento automático de inventario al pasar un pedido a «Listo».
// Cocina (o la administración) descuenta los insumos de la receta en el mismo
// lote que cambia el estado; un documento de descuento por pedido lo hace único.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-desc', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });
const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();
const now = () => serverTimestamp();

async function seedBase() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ k: 'cocina', k2: 'cocina', koff: 'cocina', w1: 'mesero',
      cash: 'cajero', admin: 'admin', super: 'superadmin' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: true });
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: uid !== 'koff', asistenciaId: `a${uid}` });
    }
    for (let i = 1; i <= 10; i++) {
      await setDoc(doc(d, 'insumos', `i${i}`), { nombre: `Insumo ${i}`, unidad: 'kg', stock: 10000, stockMinimo: 0,
        activo: true, creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    }
    for (const o of ['o1', 'o2', 'o3']) {
      await setDoc(doc(d, 'pedidos', o), { mesaId: '1', meseroId: 'w1', meseroNombre: 'Usuario w1', estado: 'registrado', revision: 2,
        cantidadDetalles: 1, detalleModificado: '', estadoCocina: 'preparando', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now(),
        registradoEn: Timestamp.now(), preparandoEn: Timestamp.now(), cocinaPor: 'k' });
    }
    await setDoc(doc(d, 'pedidos', 'pend'), { mesaId: '2', meseroId: 'w1', meseroNombre: 'Usuario w1', estado: 'registrado', revision: 1,
      cantidadDetalles: 1, detalleModificado: '', estadoCocina: 'pendiente', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now(),
      registradoEn: Timestamp.now() });
  });
}
beforeEach(seedBase);

// Lote legítimo: marcador + un movimiento y descuento por insumo [id, cantidad, stock previo] + pedido listo.
function ready(database, uid, { order = 'o1', supplies = [['i1', 1500, 10000], ['i2', 500, 10000]], marker = {}, move = {},
  supplyPatch = {}, orderPatch = {}, skipOrder = false, skipMarker = false, ids, exception } = {}) {
  const batch = writeBatch(database);
  if (!skipMarker) {
    batch.set(doc(database, 'descuentosInventario', order), { insumos: supplies.length, platosSinReceta: 0, insumosOmitidos: 0,
      creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...marker });
  }
  if (exception) batch.set(doc(database, "excepcionesInventario", order), exception);
  supplies.forEach(([id, qty, stock], n) => {
    const mid = ids?.[n] ?? `${order}_${n}`;
    batch.set(doc(database, 'movimientosInventario', mid), { insumoId: id, insumoNombre: id.replace('i', 'Insumo '), tipo: 'consumo',
      delta: -qty, stockResultante: stock - qty, motivo: '', pedidoId: order, linea: n, creadoPor: uid,
      creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...move });
    batch.update(doc(database, 'insumos', id), { stock: stock - qty, ultimoMovimiento: mid, actualizadoEn: now(), ...supplyPatch });
  });
  if (!skipOrder) {
    batch.update(doc(database, 'pedidos', order), { estadoCocina: 'listo', listoEn: now(), revision: 3, actualizadoEn: now(), ...orderPatch });
  }
  return batch.commit();
}

test('cocina marca «Listo» y descuenta en un solo lote: stock, movimientos y marcador', async () => {
  await assertSucceeds(ready(db('k'), 'k'));
  const f = db('admin');
  assert.equal((await getDoc(doc(f, 'pedidos/o1'))).data().estadoCocina, 'listo');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 8500);
  assert.equal((await getDoc(doc(f, 'insumos/i2'))).data().stock, 9500);
  const m = (await getDoc(doc(f, 'movimientosInventario/o1_0'))).data();
  assert.equal(m.tipo, 'consumo'); assert.equal(m.pedidoId, 'o1'); assert.equal(m.creadoPor, 'k'); assert.ok(m.creadoEn);
  const mk = (await getDoc(doc(f, 'descuentosInventario/o1'))).data();
  assert.equal(mk.insumos, 2); assert.equal(mk.creadoPorNombre, 'Usuario k');
});

test('Admin y Superadmin también pueden; el resto de roles no', async () => {
  await assertSucceeds(ready(db('admin'), 'admin', { order: 'o1' }));
  await assertSucceeds(ready(db('super'), 'super', { order: 'o2', supplies: [['i3', 1500, 10000]] }));
  for (const uid of ['w1', 'cash', 'koff']) await assertFails(ready(db(uid), uid, { order: 'o3' }));
});

test('un pedido sin recetas se marca «Listo» con un marcador vacío', async () => {
  await assertSucceeds(ready(db('k'), 'k', { supplies: [], marker: { platosSinReceta: 2 } }));
  assert.equal((await getDoc(doc(db('admin'), 'descuentosInventario/o1'))).data().platosSinReceta, 2);
});

test('sin el descuento no se puede pasar a «Listo», y no hay descuento sin pasar a «Listo»', async () => {
  const d = db('k');
  await assertFails(updateDoc(doc(d, 'pedidos/o1'), { estadoCocina: 'listo', listoEn: now(), revision: 3, actualizadoEn: now() }));
  await assertFails(ready(d, 'k', { skipOrder: true })); // descuento sin cambiar el estado
  await assertFails(ready(d, 'k', { skipMarker: true })); // movimientos sin marcador
  await assertFails(ready(d, 'k', { order: 'pend' })); // pedido que no está preparando
  await assertFails(setDoc(doc(d, 'descuentosInventario/o1'), { insumos: 0, platosSinReceta: 0, insumosOmitidos: 0, creadoPor: 'k',
    creadoPorNombre: 'Usuario k', creadoEn: now() })); // marcador suelto
});

test('un único descuento por pedido: no se repite ni se corrige', async () => {
  await assertSucceeds(ready(db('k'), 'k'));
  await assertFails(ready(db('k2'), 'k2')); // otro cocinero, mismo pedido
  await assertFails(updateDoc(doc(db('admin'), 'descuentosInventario/o1'), { insumos: 0 }));
  await assertFails(deleteDoc(doc(db('admin'), 'descuentosInventario/o1')));
  await assertFails(setDoc(doc(db('admin'), 'descuentosInventario/o1'), { insumos: 0, platosSinReceta: 0, insumosOmitidos: 0,
    creadoPor: 'admin', creadoPorNombre: 'Usuario admin', creadoEn: now() }));
  // otro movimiento con el mismo id de línea
  const kd = db('k');
  const b = writeBatch(kd);
  b.set(doc(kd, 'movimientosInventario/o1_0'), { insumoId: 'i3', insumoNombre: 'Insumo 3', tipo: 'consumo', delta: -1, stockResultante: 9999,
    motivo: '', pedidoId: 'o1', linea: 0, creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
  b.update(doc(kd, 'insumos/i3'), { stock: 9999, ultimoMovimiento: 'o1_0', actualizadoEn: now() });
  await assertFails(b.commit());
});

test('dos cocineros a la vez: solo uno descuenta', async () => {
  const results = await Promise.allSettled([ready(db('k'), 'k'), ready(db('k2'), 'k2')]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal((await getDoc(doc(db('admin'), 'insumos/i1'))).data().stock, 8500);
});

test('el stock no puede quedar negativo ni cambiar distinto de lo descontado', async () => {
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 10001, 10000]] })); // negativo
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 1500, 10000]], supplyPatch: { stock: 9000 } })); // stock ≠ delta
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 1500, 10000]], move: { stockResultante: 1 } }));
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 1500, 10000]], supplyPatch: { costoUnitario: 1 } })); // costo intacto
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 1500, 10000]], supplyPatch: { nombre: 'x' } }));
  await assertSucceeds(ready(db('k'), 'k', { supplies: [['i1', 10000, 10000]] })); // justo a cero
  assert.equal((await getDoc(doc(db('admin'), 'insumos/i1'))).data().stock, 0);
});

test('el consumo siempre resta, es del pedido y de su línea', async () => {
  const bad = (move, extra = {}) => assertFails(ready(db('k'), 'k', { supplies: [['i1', 1500, 10000]], move, ...extra }));
  await bad({ delta: 1500, stockResultante: 11500 }); // suma
  await bad({ delta: 0, stockResultante: 10000 });
  await bad({ delta: -1.5, stockResultante: 9998.5 });
  await bad({ tipo: 'salida' });
  await bad({ tipo: 'ajuste' });
  await bad({ motivo: 'algo' });
  await bad({ pedidoId: 'o2' }); // pedido ajeno
  await bad({ linea: 1 }); // línea fuera del marcador
  await bad({ creadoPor: 'k2' });
  await bad({ creadoPorNombre: 'Falso' });
  await bad({ creadoEn: Timestamp.now() });
  await bad({ insumoNombre: 'Falso' });
  await bad({ extra: 1 });
  await bad({}, { ids: ['otro_id'] }); // id que no es pedido_línea
});

test('el marcador cuadra con los movimientos: ni de más ni de menos', async () => {
  await assertFails(ready(db('k'), 'k', { marker: { insumos: 3 } })); // promete 3, trae 2
  await assertFails(ready(db('k'), 'k', { marker: { insumos: 1 } })); // línea 1 fuera del marcador
  await assertFails(ready(db('k'), 'k', { marker: { insumos: 9 } }));
  await assertFails(ready(db('k'), 'k', { marker: { insumos: -1 } }));
  await assertFails(ready(db('k'), 'k', { marker: { insumos: 1.5 } }));
  await assertFails(ready(db('k'), 'k', { marker: { creadoPor: 'k2' } }));
  await assertFails(ready(db('k'), 'k', { marker: { creadoPorNombre: 'Falso' } }));
  await assertFails(ready(db('k'), 'k', { marker: { creadoEn: Timestamp.now() } }));
  await assertFails(ready(db('k'), 'k', { marker: { extra: 1 } }));
  await assertFails(ready(db('k'), 'k', { marker: { platosSinReceta: -1 } }));
  await assertSucceeds(ready(db('k'), 'k'));
});

test('hasta 8 insumos por pedido (provisional); 9 se rechaza', async () => {
  const eight = Array.from({ length: 8 }, (_, i) => [`i${i + 1}`, 100, 10000]);
  await assertSucceeds(ready(db('k'), 'k', { supplies: eight }));
  const nine = Array.from({ length: 9 }, (_, i) => [`i${i + 1}`, 100, 10000]);
  await assertFails(ready(db('k'), 'k', { order: 'o2', supplies: nine, marker: { insumos: 9 } }));
});

test('un movimiento manual con el id de línea no sirve como descuento', async () => {
  const d = db('k2');
  const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/o1_0'), { insumoId: 'i1', insumoNombre: 'Insumo 1', tipo: 'entrada', delta: 1, stockResultante: 10001,
    motivo: 'Conteo', creadoPor: 'k2', creadoPorNombre: 'Usuario k2', creadoEn: now() });
  b.update(doc(d, 'insumos/i1'), { stock: 10001, ultimoMovimiento: 'o1_0', actualizadoEn: now() });
  await assertSucceeds(b.commit());
  await assertFails(ready(db('k'), 'k', { supplies: [['i2', 100, 10000]], marker: { insumos: 1 }, ids: ['otro'] }));
  // el marcador de o1 pide o1_0 con pedidoId: el manual no lo tiene
  await assertFails(ready(db('k'), 'k', { supplies: [['i2', 100, 10000]], marker: { insumos: 1 }, ids: ['o1_0'] }));
});

test('Cocina gestiona sus insumos y mueve stock con un movimiento, pero no toca costos ni recetas', async () => {
  const k = db('k');
  // Un cambio de stock sin movimiento sigue rechazado.
  await assertFails(updateDoc(doc(k, 'insumos/i1'), { stock: 5000, ultimoMovimiento: 'x', actualizadoEn: now() }));
  await assertSucceeds(updateDoc(doc(k, 'insumos/i1'), { nombre: 'Renombrado', actualizadoEn: now() }));
  // El costo ya no se escribe en el insumo, ni siquiera con la edición del catálogo.
  await assertFails(updateDoc(doc(k, 'insumos/i1'), { costoUnitario: 1, actualizadoEn: now() }));
  await assertFails(setDoc(doc(k, 'insumos/nuevo'), { nombre: 'Nuevo', unidad: 'kg', stock: 0, stockMinimo: 0, costoUnitario: 1,
    activo: true, creadoEn: now(), actualizadoEn: now() }));
  await assertSucceeds(setDoc(doc(k, 'insumos/nuevo'), { nombre: 'Nuevo', unidad: 'kg', stock: 0, stockMinimo: 0,
    activo: true, creadoEn: now(), actualizadoEn: now() }));
  const b = writeBatch(k);
  b.set(doc(k, 'movimientosInventario/m'), { insumoId: 'i1', insumoNombre: 'Renombrado', tipo: 'entrada', delta: 1000, stockResultante: 11000,
    motivo: 'Conteo', creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
  b.update(doc(k, 'insumos/i1'), { stock: 11000, ultimoMovimiento: 'm', actualizadoEn: now() });
  await assertSucceeds(b.commit());
  await assertSucceeds(getDocs(collection(k, 'movimientosInventario')));
  await assertSucceeds(getDocs(collection(k, 'descuentosInventario')));
  await assertFails(setDoc(doc(k, 'recetas/x'), { ingredientes: [], actualizadoPor: 'k', actualizadoEn: now() }));
  await assertFails(getDocs(collection(k, 'costosInsumos')));
});

test('lectura: Cocina lee insumos, recetas y descuentos; el resto de roles no', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'carta/d1'), { nombre: 'Plato' }));
  await assertSucceeds(getDocs(collection(db('k'), 'insumos')));
  await assertSucceeds(getDocs(collection(db('k'), 'recetas')));
  await assertFails(getDocs(collection(db('koff'), 'insumos')));
  for (const uid of ['w1', 'cash']) {
    await assertFails(getDocs(collection(db(uid), 'insumos')));
    await assertFails(getDocs(collection(db(uid), 'recetas')));
  }
  await assertSucceeds(ready(db('k'), 'k'));
  for (const uid of ['k', 'admin', 'super']) await assertSucceeds(getDoc(doc(db(uid), 'descuentos' + 'Inventario/o1')));
});

test('sin devolución automática: cancelar tras preparar no repone stock y nadie puede reponerlo con un consumo positivo', async () => {
  await assertSucceeds(ready(db('k'), 'k'));
  // el pedido listo no admite pasar a cancelado por la vía de cocina ni repone stock
  const d = db('admin');
  await assertFails(updateDoc(doc(d, 'insumos/i1'), { stock: 10000, ultimoMovimiento: 'o1_0', actualizadoEn: now() }));
  const b = writeBatch(d);
  b.set(doc(d, 'movimientosInventario/o1_9'), { insumoId: 'i1', insumoNombre: 'Insumo 1', tipo: 'consumo', delta: 1500, stockResultante: 10000,
    motivo: '', pedidoId: 'o1', linea: 9, creadoPor: 'admin', creadoPorNombre: 'Usuario admin', creadoEn: now() });
  b.update(doc(d, 'insumos/i1'), { stock: 10000, ultimoMovimiento: 'o1_9', actualizadoEn: now() });
  await assertFails(b.commit());
  assert.equal((await getDoc(doc(d, 'insumos/i1'))).data().stock, 8500);
  // la reposición se hace con un ajuste manual con motivo (Cocina)
  const s = db('k2'); const a = writeBatch(s);
  a.set(doc(s, 'movimientosInventario/rep'), { insumoId: 'i1', insumoNombre: 'Insumo 1', tipo: 'ajuste', delta: 1500, stockResultante: 10000,
    motivo: 'Pedido cancelado', creadoPor: 'k2', creadoPorNombre: 'Usuario k2', creadoEn: now() });
  a.update(doc(s, 'insumos/i1'), { stock: 10000, ultimoMovimiento: 'rep', actualizadoEn: now() });
  await assertSucceeds(a.commit());
});

test('un insumo desactivado no se descuenta', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { activo: false }));
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 100, 10000]] }));
});

// ---------------------------------------------------------------------------
// Excepción: Admin/Superadmin fuerzan «Listo» con stock insuficiente.
// ---------------------------------------------------------------------------
const shortage = (id = 'i1', needed = 12000, discounted = 10000) => ({ insumoId: id, insumo: id.replace('i', 'Insumo '), necesario: needed,
  descontado: discounted, faltante: needed - discounted });
const exc = (uid, extra = {}) => ({ motivo: 'Cliente esperando, repongo luego', faltantes: [shortage()], creadoPor: uid,
  creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...extra });
// Se descuenta solo lo disponible (i1: pide 12000, hay 10000 → baja a 0).
function force(database, uid, { order = 'o1', supplies = [['i1', 10000, 10000]], excOver = {}, marker = {}, ...rest } = {}) {
  return ready(database, uid, { order, supplies, marker: { forzado: true, ...marker }, exception: exc(uid, excOver), ...rest });
}

test('Admin y Superadmin fuerzan «Listo»: descuenta lo disponible, sin negativo, y deja la excepción', async () => {
  await assertSucceeds(force(db('admin'), 'admin'));
  const f = db('super');
  assert.equal((await getDoc(doc(f, 'insumos/i1'))).data().stock, 0);
  assert.equal((await getDoc(doc(f, 'pedidos/o1'))).data().estadoCocina, 'listo');
  const e = (await getDoc(doc(f, 'excepcionesInventario/o1'))).data();
  assert.equal(e.creadoPor, 'admin'); assert.equal(e.creadoPorNombre, 'Usuario admin'); assert.ok(e.creadoEn);
  assert.equal(e.faltantes[0].faltante, 2000); assert.match(e.motivo, /Cliente esperando/);
  assert.equal((await getDoc(doc(f, 'descuentosInventario/o1'))).data().forzado, true);
  assert.equal((await getDoc(doc(f, 'movimientosInventario/o1_0'))).data().delta, -10000);
  await assertSucceeds(force(db('super'), 'super', { order: 'o2', supplies: [['i2', 10000, 10000]], excOver: { faltantes: [shortage('i2')] } }));
});

test('con un insumo en cero no hay movimiento: solo la excepción y el «Listo»', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'insumos/i1'), { stock: 0 }));
  await assertSucceeds(force(db('admin'), 'admin', { supplies: [], excOver: { faltantes: [shortage('i1', 500, 0)] } }));
  assert.equal((await getDoc(doc(db('admin'), 'insumos/i1'))).data().stock, 0);
});

test('Cocina y el resto de roles no pueden forzar', async () => {
  for (const uid of ['k', 'koff', 'w1', 'cash']) await assertFails(force(db(uid), uid, { order: 'o3' }));
  // Cocina ni siquiera con el marcador marcado como forzado y sin excepción
  await assertFails(ready(db('k'), 'k', { supplies: [['i1', 10000, 10000]], marker: { forzado: true } }));
});

test('el motivo exige 10 caracteres de verdad', async () => {
  for (const motivo of ['', 'corto', '         x', '123456789', 123, 'x'.repeat(201)]) {
    await assertFails(force(db('admin'), 'admin', { excOver: { motivo } }));
  }
  await assertSucceeds(force(db('admin'), 'admin', { excOver: { motivo: '1234567890' } }));
});

test('la excepción registra usuario, hora y faltantes bien formados', async () => {
  const bad = (excOver) => assertFails(force(db('admin'), 'admin', { excOver }));
  await bad({ creadoPor: 'super' });
  await bad({ creadoPorNombre: 'Falso' });
  await bad({ creadoEn: Timestamp.now() });
  await bad({ extra: 1 });
  await bad({ faltantes: [] });
  await bad({ faltantes: 'x' });
  await bad({ faltantes: Array.from({ length: 9 }, () => shortage()) });
  await bad({ faltantes: [{ ...shortage(), faltante: 0, necesario: 10000 }] });
  await bad({ faltantes: [{ ...shortage(), necesario: 99 }] }); // no cuadra
  await bad({ faltantes: [{ ...shortage(), descontado: -1, necesario: 1999, faltante: 2000 }] });
  await bad({ faltantes: [{ ...shortage(), extra: 1 }] });
  await bad({ faltantes: [{ ...shortage(), necesario: 12000.5 }] });
  await bad({ faltantes: ['texto'] });
});

test('forzado sin excepción, o excepción sin forzado, se rechazan', async () => {
  const one = [['i1', 10000, 10000]];
  await assertFails(ready(db('admin'), 'admin', { supplies: one, marker: { forzado: true } })); // sin excepción
  await assertFails(ready(db('admin'), 'admin', { supplies: one, exception: exc('admin') })); // sin marca
  await assertFails(ready(db('admin'), 'admin', { supplies: one, marker: { forzado: false }, exception: exc('admin') }));
  await assertFails(ready(db('admin'), 'admin', { supplies: one, marker: { forzado: 'si' }, exception: exc('admin') }));
});

test('la excepción no se crea suelta ni fuera del paso a «Listo»', async () => {
  await assertFails(setDoc(doc(db('admin'), 'excepcionesInventario/o1'), exc('admin')));
  await assertFails(force(db('admin'), 'admin', { order: 'pend' })); // pedido que no está preparando
  const a = db('admin');
  const b = writeBatch(a);
  b.set(doc(a, 'excepcionesInventario/o1'), exc('admin'));
  b.update(doc(a, 'pedidos/o1'), { estadoCocina: 'listo', listoEn: now(), revision: 3, actualizadoEn: now() });
  await assertFails(b.commit()); // sin marcador ni movimientos
});

test('no se duplica: ni un segundo descuento forzado, ni la excepción se edita o borra', async () => {
  await assertSucceeds(force(db('admin'), 'admin'));
  await assertFails(force(db('super'), 'super', { supplies: [['i2', 100, 10000]], excOver: { faltantes: [shortage('i2', 200, 100)] } }));
  await assertFails(ready(db('k'), 'k', { supplies: [['i2', 100, 10000]] }));
  await assertFails(updateDoc(doc(db('admin'), 'excepcionesInventario/o1'), { motivo: 'Otro motivo largo' }));
  await assertFails(deleteDoc(doc(db('admin'), 'excepcionesInventario/o1')));
  await assertFails(setDoc(doc(db('admin'), 'excepcionesInventario/o1'), exc('admin')));
});

test('forzar no abre la puerta al stock negativo ni a consumos superiores al disponible', async () => {
  await assertFails(force(db('admin'), 'admin', { supplies: [['i1', 12000, 10000]] })); // consume más de lo que hay
  await assertFails(force(db('admin'), 'admin', { move: { stockResultante: -2000 } }));
  await assertFails(force(db('admin'), 'admin', { supplyPatch: { stock: -2000 } }));
  await assertFails(force(db('admin'), 'admin', { move: { delta: 10000 } })); // suma
  await assertFails(force(db('admin'), 'admin', { supplyPatch: { costoUnitario: 1 } }));
});

test('la excepción solo la lee la administración', async () => {
  await assertSucceeds(force(db('admin'), 'admin'));
  for (const uid of ['admin', 'super']) await assertSucceeds(getDoc(doc(db(uid), 'excepcionesInventario/o1')));
  for (const uid of ['k', 'w1', 'cash']) await assertFails(getDoc(doc(db(uid), 'excepcionesInventario/o1')));
});

test('el flujo normal de Cocina no cambia: sin forzado ni excepción sigue funcionando', async () => {
  await assertSucceeds(ready(db('k'), 'k'));
  await assertSucceeds(ready(db('k'), 'k', { order: 'o2', supplies: [['i3', 100, 10000]], marker: { forzado: false } }));
  assert.equal((await getDoc(doc(db('admin'), 'excepcionesInventario/o1'))).exists(), false);
});

test('forzado con 8 insumos faltantes (límite de lote)', async () => {
  const eight = Array.from({ length: 8 }, (_, i) => [`i${i + 1}`, 10000, 10000]);
  const faltantes = eight.map(([id]) => shortage(id));
  await assertSucceeds(force(db('admin'), 'admin', { supplies: eight, excOver: { faltantes } }));
});

// Optimización de accesos (Etapa 1): el paso a «Listo» solo consulta el último movimiento
// y los movimientos se encadenan; estas pruebas garantizan que no se perdió integridad.
test('cadena de movimientos: no se puede saltar una línea ni declarar más de las que hay', async () => {
  const d = db('k');
  const line = (b, order, n, id) => {
    b.set(doc(d, 'movimientosInventario', `${order}_${n}`), { insumoId: id, insumoNombre: id.replace('i', 'Insumo '), tipo: 'consumo',
      delta: -100, stockResultante: 9900, motivo: '', pedidoId: order, linea: n, creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
    b.update(doc(d, 'insumos', id), { stock: 9900, ultimoMovimiento: `${order}_${n}`, actualizadoEn: now() });
  };
  const head = (b, n) => b.set(doc(d, 'descuentosInventario', 'o1'), { insumos: n, platosSinReceta: 0, insumosOmitidos: 0,
    creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
  const listo = (b) => b.update(doc(d, 'pedidos', 'o1'), { estadoCocina: 'listo', listoEn: now(), revision: 3, actualizadoEn: now() });

  // líneas 0 y 2 (falta la 1) con un marcador de 3: la línea 2 exige la 1
  const skip = writeBatch(d); head(skip, 3); line(skip, 'o1', 0, 'i1'); line(skip, 'o1', 2, 'i2'); listo(skip);
  await assertFails(skip.commit());
  // marcador de 2 pero con solo la línea 0
  const short = writeBatch(d); head(short, 2); line(short, 'o1', 0, 'i1'); listo(short);
  await assertFails(short.commit());
  // la línea 1 sola, sin la 0
  const lone = writeBatch(d); head(lone, 2); line(lone, 'o1', 1, 'i1'); listo(lone);
  await assertFails(lone.commit());
  // completo
  const ok = writeBatch(d); head(ok, 2); line(ok, 'o1', 0, 'i1'); line(ok, 'o1', 1, 'i2'); listo(ok);
  await assertSucceeds(ok.commit());
});

test('el descuento exige que el pedido pase a «Listo» en el mismo lote (listoEn = hora del servidor)', async () => {
  // «Listo» con una hora cualquiera: la regla del pedido ya lo rechaza, y el descuento tampoco sirve
  await assertFails(ready(db('k'), 'k', { orderPatch: { listoEn: Timestamp.now() } }));
  // un pedido que ya está «Listo» no admite un descuento nuevo (consumo falso de stock)
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'pedidos/o1'), { estadoCocina: 'listo', listoEn: Timestamp.now() }));
  const d = db('k'); const b = writeBatch(d);
  b.set(doc(d, 'descuentosInventario', 'o1'), { insumos: 1, platosSinReceta: 0, insumosOmitidos: 0, creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
  b.set(doc(d, 'movimientosInventario', 'o1_0'), { insumoId: 'i1', insumoNombre: 'Insumo 1', tipo: 'consumo', delta: -9000, stockResultante: 1000,
    motivo: '', pedidoId: 'o1', linea: 0, creadoPor: 'k', creadoPorNombre: 'Usuario k', creadoEn: now() });
  b.update(doc(d, 'insumos/i1'), { stock: 1000, ultimoMovimiento: 'o1_0', actualizadoEn: now() });
  await assertFails(b.commit());
});
