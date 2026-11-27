// Reglas de utensilios: catálogo (Admin/Superadmin, con auditoría), movimientos
// inmutables, asignaciones por mesero y costos protegidos (el Mesero nunca los lee).
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-utensilios', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });

const db = (uid, verified = true) => env.authenticatedContext(uid, { email_verified: verified }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const now = () => serverTimestamp();

const WAITERS = ['w1', 'w2'];
const ADMINS = ['admin', 'super'];
const OUTSIDERS = ['k', 'cash', 'inactive', 'woff'];

async function seedBase() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ w1: 'mesero', w2: 'mesero', w3: 'mesero', woff: 'mesero', k: 'cocina', cash: 'cajero',
      admin: 'admin', super: 'superadmin', inactive: 'mesero' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: !['inactive', 'w3'].includes(uid) });
    }
    for (const uid of ['w1', 'w2', 'w3', 'k', 'cash', 'inactive']) {
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: true, asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'estadoAsistencia', 'woff'), { abierta: false, asistenciaId: 'awoff' });
    await setDoc(doc(d, 'utensilios/u1'), { nombre: 'Bandeja', disponible: 10, enUso: 2, stockMinimo: 3, activo: true,
      versionCosto: 1, ultimaAuditoriaId: 'seed', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'utensilios/u2'), { nombre: 'Pinza', disponible: 4, enUso: 0, stockMinimo: 0, activo: true,
      versionCosto: 0, ultimaAuditoriaId: 'seed', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'utensilios/off'), { nombre: 'Viejo', disponible: 5, enUso: 0, stockMinimo: 0, activo: false,
      versionCosto: 0, ultimaAuditoriaId: 'seed', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(d, 'costosUtensilios/u1_1'), { utensilioId: 'u1', version: 1, costoUnitario: 500,
      vigenteDesde: Timestamp.now(), creadoPor: 'admin' });
    await setDoc(doc(d, 'asignacionesUtensilios/u1_w2'), { utensilioId: 'u1', meseroId: 'w2', meseroNombre: 'Usuario w2',
      cantidad: 2, ultimoMovimiento: 'seed', actualizadoEn: Timestamp.now() });
  });
}
beforeEach(seedBase);

const NAMES = { u1: 'Bandeja', u2: 'Pinza', off: 'Viejo' };
const VERSIONS = { u1: 1, u2: 0, off: 0 };

// Movimiento completo (utensilio + asignación + movimiento) en un lote.
// `state`: existencias de partida; `held`: lo que el mesero destino tiene en uso.
function register(database, uid, { id = 'm1', utensil = 'u1', tipo = 'entrega', cantidad = 2, waiter = 'w2', state = { available: 10, inUse: 2 },
  held = 2, move = {}, utensilPatch = {}, skipAssignment = false, assignmentPatch = {}, skipUtensil = false } = {}) {
  const toWaiter = ['entrega', 'devolucion', 'perdida', 'dano', 'deterioro'].includes(tipo);
  const deltas = {
    entrega: [-cantidad, cantidad], devolucion: [cantidad, -cantidad], perdida: [0, -cantidad], dano: [0, -cantidad],
    deterioro: [0, -cantidad], alta: [cantidad, 0], ajuste: [cantidad, 0],
  }[tipo];
  const [dA, dE] = deltas;
  const available = state.available + dA;
  const inUse = state.inUse + dE;
  const batch = writeBatch(database);
  batch.set(doc(database, 'movimientosUtensilios', id), {
    utensilioId: utensil, utensilioNombre: NAMES[utensil], tipo, cantidad, deltaDisponible: dA, deltaEnUso: dE,
    disponibleResultante: available, enUsoResultante: inUse, ...(toWaiter ? { meseroId: waiter, meseroNombre: `Usuario ${waiter}` } : {}),
    versionCosto: VERSIONS[utensil], motivo: ['entrega', 'devolucion', 'alta'].includes(tipo) ? '' : 'Se rompió en servicio',
    creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: now(), ...move });
  if (!skipUtensil) {
    batch.update(doc(database, 'utensilios', utensil), { disponible: available, enUso: inUse, ultimoMovimiento: id,
      actualizadoEn: now(), ...utensilPatch });
  }
  if (toWaiter && !skipAssignment) {
    batch.set(doc(database, 'asignacionesUtensilios', `${utensil}_${waiter}`), { utensilioId: utensil, meseroId: waiter,
      meseroNombre: `Usuario ${waiter}`, cantidad: held + dE, ultimoMovimiento: id, actualizadoEn: now(), ...assignmentPatch });
  }
  return batch.commit();
}

// --------------------------------------------------------------- movimientos
test('Mesero registra entrega, devolución, pérdida, daño y deterioro, con su asignación', async () => {
  await assertSucceeds(register(db('w1'), 'w1', { id: 'a', tipo: 'entrega', cantidad: 3 }));
  const f = db('admin');
  assert.deepEqual([(await getDoc(doc(f, 'utensilios/u1'))).data().disponible, (await getDoc(doc(f, 'utensilios/u1'))).data().enUso], [7, 5]);
  assert.equal((await getDoc(doc(f, 'asignacionesUtensilios/u1_w2'))).data().cantidad, 5);
  await assertSucceeds(register(db('w1'), 'w1', { id: 'b', tipo: 'devolucion', cantidad: 1, state: { available: 7, inUse: 5 }, held: 5 }));
  await assertSucceeds(register(db('w2'), 'w2', { id: 'c', tipo: 'perdida', cantidad: 1, state: { available: 8, inUse: 4 }, held: 4 }));
  await assertSucceeds(register(db('w2'), 'w2', { id: 'd', tipo: 'dano', cantidad: 1, state: { available: 8, inUse: 3 }, held: 3 }));
  await assertSucceeds(register(db('w2'), 'w2', { id: 'e', tipo: 'deterioro', cantidad: 1, state: { available: 8, inUse: 2 }, held: 2 }));
  assert.equal((await getDoc(doc(f, 'asignacionesUtensilios/u1_w2'))).data().cantidad, 1);
  const m = (await getDoc(doc(f, 'movimientosUtensilios/c'))).data();
  assert.equal(m.meseroId, 'w2'); assert.equal(m.creadoPor, 'w2'); assert.equal(m.versionCosto, 1);
});

test('un mesero puede registrar para cualquier mesero activo; el movimiento guarda su UID y nombre', async () => {
  await assertSucceeds(register(db('w1'), 'w1', { waiter: 'w1', held: 0, state: { available: 10, inUse: 2 } }));
  const m = (await getDoc(doc(db('admin'), 'movimientosUtensilios/m1'))).data();
  assert.deepEqual([m.meseroId, m.meseroNombre, m.creadoPor], ['w1', 'Usuario w1', 'w1']);
});

test('alta y ajuste son solo de Admin y Superadmin', async () => {
  for (const tipo of ['alta', 'ajuste']) {
    for (const uid of [...WAITERS, ...OUTSIDERS]) await assertFails(register(db(uid), uid, { id: `x-${uid}`, tipo, cantidad: 3 }));
  }
  for (const uid of ADMINS) {
    await seedBase();
    await assertSucceeds(register(db(uid), uid, { id: 'alta', tipo: 'alta', cantidad: 5 }));
    await assertSucceeds(register(db(uid), uid, { id: 'aj', tipo: 'ajuste', cantidad: 1, state: { available: 15, inUse: 2 } }));
  }
});

test('un ajuste puede restar, sin dejar negativos', async () => {
  const sub = (cantidad, available) => {
    const d = db('admin');
    const b = writeBatch(d);
    b.set(doc(d, 'movimientosUtensilios/aj'), { utensilioId: 'u1', utensilioNombre: 'Bandeja', tipo: 'ajuste', cantidad,
      deltaDisponible: -cantidad, deltaEnUso: 0, disponibleResultante: available - cantidad, enUsoResultante: 2, versionCosto: 1,
      motivo: 'Conteo', creadoPor: 'admin', creadoPorNombre: 'Usuario admin', creadoEn: now() });
    b.update(doc(d, 'utensilios/u1'), { disponible: available - cantidad, ultimoMovimiento: 'aj', actualizadoEn: now() });
    return b.commit();
  };
  await assertFails(sub(11, 10)); // negativo
  await assertSucceeds(sub(4, 10));
});

test('sin stock negativo: no se entrega ni se devuelve ni se da de baja más de lo disponible o asignado', async () => {
  await assertFails(register(db('w1'), 'w1', { tipo: 'entrega', cantidad: 11 })); // disponible 10
  await assertFails(register(db('w1'), 'w1', { tipo: 'devolucion', cantidad: 3 })); // w2 tiene 2
  await assertFails(register(db('w1'), 'w1', { tipo: 'perdida', cantidad: 3 }));
  await assertFails(register(db('w1'), 'w1', { tipo: 'dano', cantidad: 3 }));
  await assertFails(register(db('w1'), 'w1', { tipo: 'deterioro', cantidad: 3 }));
  await assertFails(register(db('w1'), 'w1', { tipo: 'entrega', cantidad: 3, state: { available: 2, inUse: 2 }, utensilPatch: { disponible: -1 } }));
  // lo asignado a otro mesero no se puede devolver como propio
  await assertFails(register(db('w1'), 'w1', { tipo: 'devolucion', cantidad: 1, waiter: 'w1', held: 0 }));
});

test('cantidad: entera, positiva y acotada; los deltas deben ser los del tipo', async () => {
  for (const cantidad of [0, -1, 1.5, 'x', 1000001]) await assertFails(register(db('w1'), 'w1', { cantidad, move: { cantidad } }));
  await assertFails(register(db('w1'), 'w1', { move: { deltaDisponible: -5 } })); // delta ≠ cantidad
  await assertFails(register(db('w1'), 'w1', { move: { deltaEnUso: 5 } }));
  await assertFails(register(db('w1'), 'w1', { tipo: 'perdida', move: { deltaDisponible: -2 } })); // una baja no toca disponibles
  await assertFails(register(db('w1'), 'w1', { tipo: 'devolucion', held: 2, move: { deltaDisponible: -2, deltaEnUso: 2 } })); // al revés
});

test('el destinatario debe ser un mesero activo y su nombre el del perfil', async () => {
  for (const waiter of ['w3', 'cash', 'k', 'admin', 'nadie']) {
    await assertFails(register(db('w1'), 'w1', { waiter, held: 0 }));
  }
  await assertFails(register(db('w1'), 'w1', { move: { meseroNombre: 'Otra persona' }, assignmentPatch: { meseroNombre: 'Otra persona' } }));
});

test('los movimientos de alta y ajuste no llevan mesero; los demás sí', async () => {
  await assertFails(register(db('admin'), 'admin', { tipo: 'alta', move: { meseroId: 'w1', meseroNombre: 'Usuario w1' } }));
  const w = db('w1');
  const b = writeBatch(w);
  b.set(doc(w, 'movimientosUtensilios/sinm'), { utensilioId: 'u1', utensilioNombre: 'Bandeja', tipo: 'entrega', cantidad: 2,
    deltaDisponible: -2, deltaEnUso: 2, disponibleResultante: 8, enUsoResultante: 4, versionCosto: 1, motivo: '', creadoPor: 'w1',
    creadoPorNombre: 'Usuario w1', creadoEn: now() });
  b.update(doc(w, 'utensilios/u1'), { disponible: 8, enUso: 4, ultimoMovimiento: 'sinm', actualizadoEn: now() });
  await assertFails(b.commit());
});

test('motivo obligatorio en pérdidas, daños, deterioros y ajustes', async () => {
  for (const tipo of ['perdida', 'dano', 'deterioro']) {
    for (const motivo of ['', '  ', 'ab']) await assertFails(register(db('w2'), 'w2', { tipo, cantidad: 1, move: { motivo } }));
  }
  await assertFails(register(db('admin'), 'admin', { tipo: 'ajuste', cantidad: 1, move: { motivo: '' } }));
  await assertFails(register(db('w1'), 'w1', { move: { motivo: 'x'.repeat(121) } }));
});

test('identidad, hora y campos del movimiento', async () => {
  for (const move of [{ creadoPor: 'w2' }, { creadoPorNombre: 'Falso' }, { creadoEn: Timestamp.now() }, { extra: 1 }, { tipo: 'otro' },
    { utensilioNombre: 'Falso' }, { utensilioId: 'u2' }, { versionCosto: 2 }, { versionCosto: 0 }, { disponibleResultante: 99 }, { enUsoResultante: 99 }]) {
    await assertFails(register(db('w1'), 'w1', { move }));
  }
});

test('un movimiento y su efecto van juntos: sin uno no hay otro', async () => {
  await assertFails(register(db('w1'), 'w1', { skipUtensil: true })); // movimiento sin cambiar existencias
  await assertFails(register(db('w1'), 'w1', { skipAssignment: true })); // sin asignación del mesero
  const w = db('w1');
  const b = writeBatch(w);
  b.update(doc(w, 'utensilios/u1'), { disponible: 8, enUso: 4, ultimoMovimiento: 'fantasma', actualizadoEn: now() });
  await assertFails(b.commit()); // existencias sin movimiento
  await assertFails(updateDoc(doc(db('w1'), 'utensilios/u1'), { disponible: 99, actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('admin'), 'utensilios/u1'), { disponible: 99, actualizadoEn: now() })); // ni el admin
});

test('la asignación solo cambia con su movimiento y por la cantidad exacta', async () => {
  await assertFails(register(db('w1'), 'w1', { assignmentPatch: { cantidad: 99 } }));
  await assertFails(register(db('w1'), 'w1', { assignmentPatch: { utensilioId: 'u2' } }));
  await assertFails(register(db('w1'), 'w1', { assignmentPatch: { ultimoMovimiento: 'otro' } }));
  await assertFails(register(db('w1'), 'w1', { assignmentPatch: { extra: 1 } }));
  await assertFails(updateDoc(doc(db('w1'), 'asignacionesUtensilios/u1_w2'), { cantidad: 0, actualizadoEn: now() }));
  await assertFails(setDoc(doc(db('admin'), 'asignacionesUtensilios/u1_w1'), { utensilioId: 'u1', meseroId: 'w1', meseroNombre: 'Usuario w1',
    cantidad: 50, ultimoMovimiento: 'x', actualizadoEn: now() }));
  await assertFails(deleteDoc(doc(db('admin'), 'asignacionesUtensilios/u1_w2')));
});

test('un utensilio desactivado no recibe movimientos', async () => {
  await assertFails(register(db('admin'), 'admin', { utensil: 'off', tipo: 'alta', cantidad: 1, state: { available: 5, inUse: 0 } }));
});

test('los movimientos son inmutables y no se borran', async () => {
  await assertSucceeds(register(db('w1'), 'w1'));
  for (const uid of ['w1', 'w2', ...ADMINS]) {
    await assertFails(updateDoc(doc(db(uid), 'movimientosUtensilios/m1'), { cantidad: 1 }));
    await assertFails(updateDoc(doc(db(uid), 'movimientosUtensilios/m1'), { motivo: 'cambiado' }));
    await assertFails(deleteDoc(doc(db(uid), 'movimientosUtensilios/m1')));
  }
  // no se reutiliza el id de un movimiento existente
  await assertFails(register(db('w1'), 'w1', { state: { available: 8, inUse: 4 }, held: 4 }));
});

// -------------------------------------------------------------------- lectura
test('lectura: Mesero, Admin y Superadmin; Cocina, Cajero, inactivos y sin jornada, no', async () => {
  await assertSucceeds(register(db('w1'), 'w1'));
  for (const uid of [...WAITERS, ...ADMINS]) {
    for (const c of ['utensilios', 'asignacionesUtensilios', 'movimientosUtensilios']) await assertSucceeds(getDocs(collection(db(uid), c)));
  }
  for (const uid of OUTSIDERS) {
    for (const c of ['utensilios', 'asignacionesUtensilios', 'movimientosUtensilios']) await assertFails(getDocs(collection(db(uid), c)));
  }
  await assertFails(getDocs(collection(anon(), 'utensilios')));
  await assertFails(getDocs(collection(db('w1', false), 'utensilios')));
});

test('Admin y Superadmin leen sin necesitar jornada; el mesero la necesita', async () => {
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'estadoAsistencia/w1'), { abierta: false }));
  await assertFails(getDocs(collection(db('w1'), 'utensilios')));
  await assertFails(register(db('w1'), 'w1'));
  await assertSucceeds(getDocs(collection(db('admin'), 'utensilios')));
});

// --------------------------------------------------------------------- costos
test('los costos de utensilios los lee y crea solo la administración; el mesero jamás', async () => {
  for (const uid of ADMINS) await assertSucceeds(getDoc(doc(db(uid), 'costosUtensilios/u1_1')));
  for (const uid of [...WAITERS, ...OUTSIDERS]) {
    await assertFails(getDoc(doc(db(uid), 'costosUtensilios/u1_1')));
    await assertFails(getDocs(collection(db(uid), 'costosUtensilios')));
  }
  await assertFails(getDoc(doc(anon(), 'costosUtensilios/u1_1')));
});

test('ningún documento legible por el mesero lleva importes', async () => {
  // Intentos de colar dinero en el utensilio o en un movimiento.
  await assertFails(updateDoc(doc(db('admin'), 'utensilios/u1'), { costoUnitario: 500, ultimaAuditoriaId: 'x', actualizadoEn: now() }));
  for (const money of [{ costoUnitario: 500 }, { valor: 1000 }, { costo: 5 }, { precio: 5 }]) {
    await assertFails(register(db('w1'), 'w1', { move: money }));
    await assertFails(register(db('admin'), 'admin', { id: 'adm', tipo: 'alta', move: money }));
  }
  const stored = (await getDoc(doc(db('admin'), 'utensilios/u1'))).data();
  assert.equal(Object.keys(stored).some((k) => /costo(?!s)|valor|precio/i.test(k) && k !== 'versionCosto'), false);
});

// ------------------------------------------------------------------- catálogo
// Alta o edición con su entrada de auditoría en el mismo lote.
function audit(database, id, uid, target, accion = 'crear_utensilio') {
  return [doc(database, 'auditoria', id), { accion, actorUid: uid, actorNombre: `Usuario ${uid}`, objetivo: target, campos: ['nombre'], creadoEn: now() }];
}
const newUtensil = (auditId, extra = {}) => ({ nombre: 'Cuchara', disponible: 0, enUso: 0, stockMinimo: 5, activo: true, versionCosto: 0,
  ultimaAuditoriaId: auditId, creadoEn: now(), actualizadoEn: now(), ...extra });

test('alta del catálogo: Admin y Superadmin, con auditoría, sin existencias y sin costo (o versión 1)', async () => {
  for (const uid of ADMINS) {
    const d = db(uid);
    const b = writeBatch(d);
    b.set(...audit(d, `au-${uid}`, uid, `n-${uid}`));
    b.set(doc(d, 'utensilios', `n-${uid}`), newUtensil(`au-${uid}`));
    await assertSucceeds(b.commit());
  }
  // con costo inicial: versión 1 en el mismo lote
  const a = db('admin');
  const b = writeBatch(a);
  b.set(...audit(a, 'au-c', 'admin', 'con-costo'));
  b.set(doc(a, 'costosUtensilios/con-costo_1'), { utensilioId: 'con-costo', version: 1, costoUnitario: 250, vigenteDesde: now(), creadoPor: 'admin' });
  b.set(doc(a, 'utensilios/con-costo'), newUtensil('au-c', { versionCosto: 1 }));
  await assertSucceeds(b.commit());
  assert.equal((await getDoc(doc(db('super'), 'costosUtensilios/con-costo_1'))).data().costoUnitario, 250);
});

test('alta del catálogo sin auditoría o con una auditoría ajena se rechaza', async () => {
  const a = db('admin');
  const noAudit = writeBatch(a);
  noAudit.set(doc(a, 'utensilios/x'), newUtensil('inexistente'));
  await assertFails(noAudit.commit());
  const wrongTarget = writeBatch(a);
  wrongTarget.set(...audit(a, 'au1', 'admin', 'otro-objetivo'));
  wrongTarget.set(doc(a, 'utensilios/x'), newUtensil('au1'));
  await assertFails(wrongTarget.commit());
  const wrongActor = writeBatch(a);
  wrongActor.set(...audit(a, 'au2', 'super', 'x'));
  wrongActor.set(doc(a, 'utensilios/x'), newUtensil('au2'));
  await assertFails(wrongActor.commit());
});

test('alta del catálogo: nadie más y nada de existencias iniciales ni campos extra', async () => {
  for (const uid of [...WAITERS, ...OUTSIDERS]) {
    const d = db(uid);
    const b = writeBatch(d);
    b.set(doc(d, 'utensilios/x'), newUtensil('a'));
    await assertFails(b.commit());
  }
  for (const extra of [{ disponible: 5 }, { enUso: 1 }, { nombre: 'a' }, { stockMinimo: -1 }, { stockMinimo: 1.5 }, { activo: false },
    { versionCosto: 2 }, { versionCosto: 1 }, { costoUnitario: 100 }, { extra: 1 }, { creadoEn: Timestamp.now() }]) {
    const d = db('admin');
    const b = writeBatch(d);
    b.set(...audit(d, 'au', 'admin', 'x'));
    b.set(doc(d, 'utensilios/x'), newUtensil('au', extra));
    await assertFails(b.commit());
  }
});

test('edición del catálogo: nombre, mínimo y activo, con auditoría nueva; no toca las existencias', async () => {
  const edit = (uid, patch, auditId = 'au-e', target = 'u2') => {
    const d = db(uid);
    const b = writeBatch(d);
    b.set(...audit(d, auditId, uid, target, 'editar_utensilio'));
    b.update(doc(d, 'utensilios/u2'), { ultimaAuditoriaId: auditId, actualizadoEn: now(), ...patch });
    return b.commit();
  };
  await assertSucceeds(edit('admin', { nombre: 'Pinza grande', stockMinimo: 2, activo: false }));
  await assertSucceeds(edit('super', { nombre: 'Pinza' }, 'au-e2'));
  await assertFails(edit('admin', { disponible: 99 }, 'au-e3'));
  await assertFails(edit('admin', { enUso: 5 }, 'au-e3'));
  await assertFails(edit('admin', { nombre: 'x' }, 'au-e3'));
  await assertFails(edit('admin', { stockMinimo: -1 }, 'au-e3'));
  await assertFails(edit('admin', { costoUnitario: 5 }, 'au-e3'));
  await assertFails(edit('admin', { nombre: 'Otra' }, 'au-e4', 'otro-objetivo')); // auditoría de otro objetivo
  // sin cambiar el id de auditoría
  await assertFails(updateDoc(doc(db('admin'), 'utensilios/u2'), { nombre: 'Sin rastro', actualizadoEn: now() }));
  await assertFails(updateDoc(doc(db('admin'), 'utensilios/u2'), { nombre: 'Sin rastro', ultimaAuditoriaId: 'seed', actualizadoEn: now() }));
  for (const uid of [...WAITERS, ...OUTSIDERS]) {
    const d = db(uid);
    const b = writeBatch(d);
    b.update(doc(d, 'utensilios/u2'), { nombre: 'Hackeado', ultimaAuditoriaId: 'a', actualizadoEn: now() });
    await assertFails(b.commit());
  }
  for (const uid of [...ADMINS, 'w1']) await assertFails(deleteDoc(doc(db(uid), 'utensilios/u1')));
});

test('el costo se versiona: versión +1 con su documento inmutable, solo Admin', async () => {
  const newCost = (uid, version, { patch = {}, cost = {}, skipCost = false } = {}) => {
    const d = db(uid);
    const b = writeBatch(d);
    b.set(...audit(d, `au-${version}`, uid, 'u1', 'editar_utensilio'));
    if (!skipCost) {
      b.set(doc(d, 'costosUtensilios', `u1_${version}`), { utensilioId: 'u1', version, costoUnitario: 650,
        vigenteDesde: now(), creadoPor: uid, ...cost });
    }
    b.update(doc(d, 'utensilios/u1'), { versionCosto: version, ultimaAuditoriaId: `au-${version}`, actualizadoEn: now(), ...patch });
    return b.commit();
  };
  await assertFails(newCost('admin', 2, { skipCost: true })); // versión sin documento de costo
  await assertFails(newCost('admin', 3)); // salto de versión
  await assertFails(newCost('admin', 2, { cost: { version: 3 } }));
  await assertFails(newCost('admin', 2, { cost: { costoUnitario: -1 } }));
  await assertFails(newCost('admin', 2, { cost: { costoUnitario: 1.5 } }));
  await assertFails(newCost('admin', 2, { cost: { creadoPor: 'super' } }));
  await assertFails(newCost('admin', 2, { cost: { vigenteDesde: Timestamp.now() } }));
  await assertFails(newCost('admin', 2, { cost: { extra: 1 } }));
  await assertSucceeds(newCost('admin', 2));
  // las versiones son inmutables y no se borran
  for (const uid of ADMINS) {
    await assertFails(updateDoc(doc(db(uid), 'costosUtensilios/u1_1'), { costoUnitario: 1 }));
    await assertFails(deleteDoc(doc(db(uid), 'costosUtensilios/u1_2')));
  }
  // el movimiento posterior toma la versión vigente (2), la anterior (1) ya no sirve
  await assertFails(register(db('w1'), 'w1', { id: 'v1', move: { versionCosto: 1 } }));
  VERSIONS.u1 = 2;
  try {
    await assertSucceeds(register(db('w1'), 'w1', { id: 'v2' }));
  } finally { VERSIONS.u1 = 1; }
});

test('el mesero no puede crear versiones de costo ni documentos de costo sueltos', async () => {
  for (const uid of [...WAITERS, ...OUTSIDERS]) {
    await assertFails(setDoc(doc(db(uid), 'costosUtensilios/u1_2'), { utensilioId: 'u1', version: 2, costoUnitario: 1, vigenteDesde: now(), creadoPor: uid }));
  }
  // un documento de costo sin versionCosto del utensilio en el mismo lote
  await assertFails(setDoc(doc(db('admin'), 'costosUtensilios/u1_2'), { utensilioId: 'u1', version: 2, costoUnitario: 1, vigenteDesde: now(), creadoPor: 'admin' }));
});

test('una pérdida se valora con la versión de costo de su movimiento, aunque el costo cambie después', async () => {
  await assertSucceeds(register(db('w2'), 'w2', { id: 'loss', tipo: 'perdida', cantidad: 1, held: 2 }));
  const m = (await getDoc(doc(db('admin'), 'movimientosUtensilios/loss'))).data();
  const cost = (await getDoc(doc(db('admin'), `costosUtensilios/${m.utensilioId}_${m.versionCosto}`))).data().costoUnitario;
  assert.equal(cost * m.cantidad, 500);
  assert.equal('valor' in m || 'costoUnitario' in m, false); // el mesero no ve ese valor
});

// ------------------------------------------------------- directorio de meseros
const dirEntry = (name, active, extra = {}) => ({ nombre: name, activo: active, actualizadoEn: now(), ...extra });

test('directorio de meseros: lo leen Mesero y administración; Cocina, Cajero y sin jornada, no', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'directorioMeseros/w1'), { nombre: 'Usuario w1', activo: true, actualizadoEn: Timestamp.now() }));
  for (const uid of [...WAITERS, ...ADMINS]) await assertSucceeds(getDocs(collection(db(uid), 'directorioMeseros')));
  for (const uid of OUTSIDERS) await assertFails(getDocs(collection(db(uid), 'directorioMeseros')));
  await assertFails(getDocs(collection(anon(), 'directorioMeseros')));
});

test('directorio de meseros: solo la administración lo escribe y debe coincidir con el perfil', async () => {
  for (const uid of ADMINS) {
    await assertSucceeds(setDoc(doc(db(uid), 'directorioMeseros/w1'), dirEntry('Usuario w1', true)));
  }
  // un mesero inactivo (w3) se refleja como inactivo; marcarlo activo se rechaza
  await assertSucceeds(setDoc(doc(db('admin'), 'directorioMeseros/w3'), dirEntry('Usuario w3', false)));
  await assertFails(setDoc(doc(db('admin'), 'directorioMeseros/w3'), dirEntry('Usuario w3', true)));
  // quien no es mesero nunca figura como activo
  await assertFails(setDoc(doc(db('admin'), 'directorioMeseros/k'), dirEntry('Usuario k', true)));
  await assertSucceeds(setDoc(doc(db('admin'), 'directorioMeseros/k'), dirEntry('Usuario k', false)));
  // nombre distinto del perfil, campos extra o ausentes, hora falsa
  for (const bad of [dirEntry('Otro nombre', true), dirEntry('Usuario w1', true, { email: 'x@y.z' }),
    dirEntry('Usuario w1', true, { actualizadoEn: Timestamp.now() }), { nombre: 'Usuario w1', actualizadoEn: now() }]) {
    await assertFails(setDoc(doc(db('admin'), 'directorioMeseros/w1'), bad));
  }
  for (const uid of [...WAITERS, ...OUTSIDERS]) await assertFails(setDoc(doc(db(uid), 'directorioMeseros/w1'), dirEntry('Usuario w1', true)));
  await assertFails(deleteDoc(doc(db('admin'), 'directorioMeseros/w1')));
});

test('el directorio no concede nada: el destinatario sigue validándose contra el perfil', async () => {
  // aparece como activo en el directorio, pero su perfil está inactivo (w3)
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'directorioMeseros/w3'), { nombre: 'Usuario w3', activo: true, actualizadoEn: Timestamp.now() }));
  await assertFails(register(db('w1'), 'w1', { waiter: 'w3', held: 0 }));
});
