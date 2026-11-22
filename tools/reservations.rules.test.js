// Reglas de reservaciones (Fase 4). Se ejecuta contra el emulador de Firestore.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-reservas', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });

const HOUR = 3600 * 1000;
const at = (hours) => Timestamp.fromDate(new Date(Date.now() + hours * HOUR));
const db = (uid, verified = true) => env.authenticatedContext(uid, { email_verified: verified }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const now = () => serverTimestamp();

function data(uid, extra = {}) {
  return { mesaId: '4', cliente: 'Rosa Díaz', telefono: '987 654 321', personas: 3, fechaHora: at(24), notas: '',
    estado: 'pendiente', creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), actualizadoEn: now(), ...extra };
}
const seeded = (extra = {}) => ({ ...data('w1'), creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now(), ...extra });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ w1: 'mesero', w2: 'mesero', admin: 'admin', super: 'superadmin',
      k: 'cocina', cash: 'cajero', stock: 'almacen', off: 'mesero' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: true });
    }
    for (const uid of ['w1', 'w2', 'k', 'cash', 'off']) {
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: uid !== 'off', asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'mesas/4'), { numero: '4', capacidad: 4, activo: true, pedidoActivo: null });
    await setDoc(doc(d, 'mesas/9'), { numero: '9', capacidad: 8, activo: false, pedidoActivo: null });
    await setDoc(doc(d, 'mesas/5'), { numero: '5', capacidad: 4, activo: true, pedidoActivo: 'p5' });
    await setDoc(doc(d, 'pedidos/p5'), { mesaId: '5', meseroId: 'w1', meseroNombre: 'Usuario w1', estado: 'abierto',
      revision: 0, cantidadDetalles: 0, detalleModificado: '', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'reservaciones/pend'), seeded());
    await setDoc(doc(d, 'reservaciones/conf'), seeded({ estado: 'confirmada' }));
    await setDoc(doc(d, 'reservaciones/pasada'), seeded({ estado: 'confirmada', fechaHora: at(-1) }));
    await setDoc(doc(d, 'reservaciones/cancelada'), seeded({ estado: 'cancelada', motivoCancelacion: 'Llamó' }));
  });
});

const patch = (database, id, fields) => updateDoc(doc(database, 'reservaciones', id), { actualizadoEn: now(), ...fields });

test('admin, superadmin y mesero con jornada abierta crean reservaciones', async () => {
  for (const uid of ['admin', 'super', 'w1']) {
    await assertSucceeds(setDoc(doc(db(uid), 'reservaciones', `n-${uid}`), data(uid)));
  }
});

test('cocina, almacén, anónimo, inactivo, sin jornada o sin correo verificado no crean', async () => {
  for (const uid of ['k', 'cash', 'stock', 'off']) {
    await assertFails(setDoc(doc(db(uid), 'reservaciones', 'x'), data(uid)));
  }
  await assertFails(setDoc(doc(anon(), 'reservaciones', 'x'), data('w1')));
  await assertFails(setDoc(doc(db('w1', false), 'reservaciones', 'x'), data('w1')));
});

test('lectura: personal de sala y caja con jornada; el resto no', async () => {
  for (const uid of ['admin', 'super', 'w1', 'w2', 'cash']) {
    await assertSucceeds(getDocs(collection(db(uid), 'reservaciones')));
  }
  for (const uid of ['k', 'stock', 'off']) await assertFails(getDocs(collection(db(uid), 'reservaciones')));
  await assertFails(getDocs(collection(anon(), 'reservaciones')));
  await assertFails(getDoc(doc(db('w1', false), 'reservaciones/pend')));
});

test('la cajera solo consulta', async () => {
  await assertFails(setDoc(doc(db('cash'), 'reservaciones', 'x'), data('cash')));
  await assertFails(patch(db('cash'), 'pend', { estado: 'confirmada' }));
});

test('datos inválidos se rechazan al crear', async () => {
  const bad = [
    { cliente: 'A' }, { cliente: 'x'.repeat(81) }, { telefono: 'abc' }, { telefono: '123' }, { personas: 0 },
    { personas: 51 }, { personas: 2.5 }, { notas: 'x'.repeat(301) }, { mesaId: '01' }, { fechaHora: 'mañana' },
    { fechaHora: at(-1) }, { personas: 5 /* excede la capacidad de la mesa 4 */ }, { mesaId: '9' /* inactiva */ },
    { mesaId: '77' /* no existe */ }, { estado: 'confirmada' }, { estado: 'cumplida' }, { extra: true },
    { pedidoId: 'p5' }, { motivoCancelacion: 'Llamó' }, { creadoPor: 'w2' }, { creadoPorNombre: 'Falso' },
    { creadoEn: Timestamp.now() }, { actualizadoEn: Timestamp.now() },
  ];
  for (const extra of bad) {
    await assertFails(setDoc(doc(db('w1'), 'reservaciones', 'x'), data('w1', extra)));
  }
  const missing = data('w1'); delete missing.notas;
  await assertFails(setDoc(doc(db('w1'), 'reservaciones', 'x'), missing));
});

test('edición: cambia datos pendientes o confirmadas con mesa y fecha válidas', async () => {
  await assertSucceeds(patch(db('w2'), 'pend', { cliente: 'Luis Soto', personas: 4, fechaHora: at(30), notas: 'Cumpleaños' }));
  await assertSucceeds(patch(db('admin'), 'conf', { telefono: '999888777' }));
  for (const fields of [{ personas: 9 }, { mesaId: '9' }, { mesaId: '77' }, { fechaHora: at(-2) }, { cliente: 'x' },
    { telefono: 'zz' }, { creadoPor: 'w2' }, { creadoEn: Timestamp.now() }, { extra: 1 }]) {
    await assertFails(patch(db('w1'), 'pend', fields));
  }
});

test('confirmar sí; volver a pendiente o saltar a estados no permitidos no', async () => {
  await assertSucceeds(patch(db('w1'), 'pend', { estado: 'confirmada' }));
  await assertFails(patch(db('w1'), 'conf', { estado: 'pendiente' }));
  await assertFails(patch(db('w1'), 'pend', { estado: 'cumplida', pedidoId: 'p5' })); // debe estar confirmada
  await assertFails(patch(db('w1'), 'pend', { estado: 'inventado' }));
  await assertFails(patch(db('w1'), 'conf', { estado: 'confirmada', fechaHora: at(-3) })); // pasada
});

test('cancelar exige motivo y no toca otros datos', async () => {
  await assertFails(patch(db('w1'), 'pend', { estado: 'cancelada' }));
  await assertFails(patch(db('w1'), 'pend', { estado: 'cancelada', motivoCancelacion: 'ab' }));
  await assertFails(patch(db('w1'), 'pend', { estado: 'cancelada', motivoCancelacion: 'x'.repeat(201) }));
  await assertFails(patch(db('w1'), 'pend', { estado: 'cancelada', motivoCancelacion: 'Llamó', cliente: 'Otro' }));
  await assertSucceeds(patch(db('w1'), 'pend', { estado: 'cancelada', motivoCancelacion: 'Llamó para cancelar' }));
  await assertSucceeds(patch(db('admin'), 'conf', { estado: 'cancelada', motivoCancelacion: 'Cierre del local' }));
});

test('sentar: solo confirmadas, enlazadas a un pedido real de la misma mesa', async () => {
  await assertFails(patch(db('w1'), 'conf', { estado: 'cumplida' })); // sin pedido
  await assertFails(patch(db('w1'), 'conf', { estado: 'cumplida', pedidoId: 'no-existe' }));
  await assertFails(patch(db('w1'), 'conf', { estado: 'cumplida', pedidoId: 'p5' })); // pedido de la mesa 5, no la 4
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'pedidos/p4'), { mesaId: '4', meseroId: 'w1',
    meseroNombre: 'Usuario w1', estado: 'abierto', revision: 0, cantidadDetalles: 0, detalleModificado: '',
    creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() }));
  await assertSucceeds(patch(db('w1'), 'conf', { estado: 'cumplida', pedidoId: 'p4' }));
  assert.equal((await getDoc(doc(db('admin'), 'reservaciones/conf'))).data().pedidoId, 'p4');
});

test('«No asistió» solo pasada la hora', async () => {
  await assertFails(patch(db('w1'), 'conf', { estado: 'noAsistio' }));
  await assertSucceeds(patch(db('w1'), 'pasada', { estado: 'noAsistio' }));
});

test('los estados finales son inmutables y nada se borra', async () => {
  for (const uid of ['w1', 'admin', 'super']) {
    await assertFails(patch(db(uid), 'cancelada', { estado: 'confirmada' }));
    await assertFails(patch(db(uid), 'cancelada', { motivoCancelacion: 'Otro motivo' }));
    await assertFails(deleteDoc(doc(db(uid), 'reservaciones/pend')));
  }
  await patch(db('w1'), 'pasada', { estado: 'noAsistio' });
  await assertFails(patch(db('admin'), 'pasada', { estado: 'confirmada' }));
});

test('sin jornada abierta no se edita ni se cancela', async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'estadoAsistencia', 'w1'), { abierta: false }));
  await assertFails(patch(db('w1'), 'pend', { estado: 'confirmada' }));
  await assertFails(getDoc(doc(db('w1'), 'reservaciones/pend')));
  // El administrador está exento.
  await assertSucceeds(patch(db('admin'), 'pend', { estado: 'confirmada' }));
});
