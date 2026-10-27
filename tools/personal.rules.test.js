// Reglas de gestión de personal, bajas, restricciones y auditoría.
const { test, before, after, beforeEach } = require('node:test');
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, writeBatch, serverTimestamp } = require('firebase/firestore');
const { createEnv, staff } = require('./support');

let env;
before(async () => { env = await createEnv(); });
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'usuarios/super'), staff({ nombres: 'Sofia', rol: 'superadmin', numeroDocumento: '11111111' }));
    await setDoc(doc(db, 'usuarios/admin'), staff({ nombres: 'Adan', rol: 'admin', numeroDocumento: '22222222' }));
    await setDoc(doc(db, 'usuarios/admin2'), staff({ nombres: 'Alba', rol: 'admin', numeroDocumento: '33333333' }));
    await setDoc(doc(db, 'usuarios/mesero'), staff({ nombres: 'Mario', rol: 'mesero', numeroDocumento: '44444444' }));
    await setDoc(doc(db, 'usuarios/baja'), staff({ nombres: 'Bruno', rol: 'cocina', estado: 'baja', activo: false, numeroDocumento: '55555555' }));
    await setDoc(doc(db, 'documentos/44444444'), { uid: 'mesero' });
    await setDoc(doc(db, 'correos/mario@granja.pe'), { uid: 'mesero' });
    await setDoc(doc(db, 'documentos/55555555'), { uid: 'baja' });
    await setDoc(doc(db, 'correos/bruno@granja.pe'), { uid: 'baja' });
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

/** Alta completa: ficha + índices + auditoría en un solo lote. */
function altaBatch(db, actor, uid, overrides = {}) {
  const data = staff({ nombres: 'Nuevo', apellidos: 'Trabajador', numeroDocumento: '66666666', ...overrides });
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/a1'), {
    accion: 'crear_trabajador', actorUid: actor, actorNombre: 'X', objetivo: uid, campos: [], creadoEn: serverTimestamp(),
  });
  b.set(doc(db, `usuarios/${uid}`), {
    ...data, ultimaAuditoriaId: 'a1', creadoEn: serverTimestamp(), creadoPor: actor, actualizadoEn: serverTimestamp(),
  });
  b.set(doc(db, `documentos/${data.numeroDocumento}`), { uid, creadoEn: serverTimestamp() });
  b.set(doc(db, `correos/${data.email}`), { uid, creadoEn: serverTimestamp() });
  return b;
}

test('admin crea un trabajador operativo', () =>
  assertSucceeds(altaBatch(as('admin'), 'admin', 'nuevo').commit()));

test('admin no crea administradores; superadmin sí', async () => {
  await assertFails(altaBatch(as('admin'), 'admin', 'nuevo', { rol: 'admin' }).commit());
  await assertSucceeds(altaBatch(as('super'), 'super', 'nuevo', { rol: 'admin' }).commit());
});

test('nadie crea superadmins desde la app', () =>
  assertFails(altaBatch(as('super'), 'super', 'nuevo', { rol: 'superadmin' }).commit()));

test('mesero no crea trabajadores', () =>
  assertFails(altaBatch(as('mesero'), 'mesero', 'nuevo').commit()));

test('documento duplicado se rechaza, incluso de un trabajador dado de baja', async () => {
  await assertFails(altaBatch(as('admin'), 'admin', 'n1', { numeroDocumento: '44444444' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n2', { numeroDocumento: '55555555' }).commit());
});

test('correo duplicado se rechaza, incluso de un trabajador dado de baja', async () => {
  await assertFails(altaBatch(as('admin'), 'admin', 'n1', { email: 'mario@granja.pe' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n2', { email: 'bruno@granja.pe' }).commit());
});

test('formatos inválidos se rechazan', async () => {
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { numeroDocumento: '1234567' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { celular: '12345678' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { celularAlterno: '123' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { email: 'sin-arroba' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { email: 'Mayus@granja.pe' }).commit());
  await assertFails(altaBatch(as('admin'), 'admin', 'n', { tipoDocumento: 'ce', numeroDocumento: '123' }).commit());
  await assertSucceeds(altaBatch(as('admin'), 'admin', 'n', { tipoDocumento: 'ce', numeroDocumento: 'ABC123456' }).commit());
});

test('el alta sin auditoría se rechaza', async () => {
  const db = as('admin');
  const data = staff({ numeroDocumento: '66666666', nombres: 'Nuevo' });
  const b = writeBatch(db);
  b.set(doc(db, 'usuarios/nuevo'), {
    ...data, ultimaAuditoriaId: 'inexistente', creadoEn: serverTimestamp(), creadoPor: 'admin', actualizadoEn: serverTimestamp(),
  });
  b.set(doc(db, 'documentos/66666666'), { uid: 'nuevo', creadoEn: serverTimestamp() });
  b.set(doc(db, `correos/${data.email}`), { uid: 'nuevo', creadoEn: serverTimestamp() });
  await assertFails(b.commit());
});

function editBatch(db, actor, uid, changes, auditId = 'e1') {
  const b = writeBatch(db);
  b.set(doc(db, `auditoria/${auditId}`), {
    accion: 'editar_trabajador', actorUid: actor, actorNombre: 'X', objetivo: uid, campos: Object.keys(changes), creadoEn: serverTimestamp(),
  });
  b.update(doc(db, `usuarios/${uid}`), { ...changes, actualizadoEn: serverTimestamp(), ultimaAuditoriaId: auditId });
  return b;
}

test('admin edita datos de un trabajador operativo', () =>
  assertSucceeds(editBatch(as('admin'), 'admin', 'mesero', { celular: '911111111' }).commit()));

test('admin no edita a otro admin ni a un superadmin', async () => {
  await assertFails(editBatch(as('admin'), 'admin', 'admin2', { celular: '911111111' }).commit());
  await assertFails(editBatch(as('admin'), 'admin', 'super', { celular: '911111111' }).commit());
});

test('no hay escalamiento de privilegios', async () => {
  await assertFails(editBatch(as('admin'), 'admin', 'mesero', { rol: 'admin' }).commit());
  await assertFails(editBatch(as('admin'), 'admin', 'admin', { rol: 'superadmin' }).commit());
  await assertFails(editBatch(as('super'), 'super', 'mesero', { rol: 'superadmin' }).commit());
  await assertSucceeds(editBatch(as('super'), 'super', 'mesero', { rol: 'admin' }).commit());
});

test('nadie se edita a sí mismo', async () => {
  await assertFails(editBatch(as('admin'), 'admin', 'admin', { celular: '911111111' }).commit());
  await assertFails(editBatch(as('super'), 'super', 'super', { celular: '911111111' }).commit());
  await assertFails(editBatch(as('mesero'), 'mesero', 'mesero', { celular: '911111111' }).commit());
});

test('documento y correo no se pueden modificar', async () => {
  await assertFails(editBatch(as('admin'), 'admin', 'mesero', { numeroDocumento: '99999999' }).commit());
  await assertFails(editBatch(as('admin'), 'admin', 'mesero', { email: 'otro@granja.pe' }).commit());
});

test('la edición sin auditoría se rechaza', () =>
  assertFails(updateOnly(as('admin'), 'mesero', { celular: '911111111' })));

async function updateOnly(db, uid, changes) {
  const b = writeBatch(db);
  b.update(doc(db, `usuarios/${uid}`), { ...changes, actualizadoEn: serverTimestamp(), ultimaAuditoriaId: 'nada' });
  return b.commit();
}

test('solo el superadmin autoriza a un admin a regularizar', async () => {
  await assertFails(editBatch(as('admin'), 'admin', 'mesero', { puedeRegularizar: true }).commit());
  await assertFails(editBatch(as('super'), 'super', 'mesero', { puedeRegularizar: true }).commit());
  await assertSucceeds(editBatch(as('super'), 'super', 'admin2', { puedeRegularizar: true }).commit());
});

function estadoBatch(db, actor, uid, { estado, tipo, motivo = 'Motivo suficientemente largo', bajaTipo }) {
  const b = writeBatch(db);
  b.set(doc(db, 'movimientosPersonal/m1'), {
    uid, tipo, estadoNuevo: estado, motivo, actorUid: actor, creadoEn: serverTimestamp(),
  });
  b.set(doc(db, 'auditoria/s1'), {
    accion: 'cambiar_estado', actorUid: actor, actorNombre: 'X', objetivo: uid, campos: ['estado'], creadoEn: serverTimestamp(),
  });
  const change = {
    estado, activo: estado === 'activo', ultimoMovimientoId: 'm1', actualizadoEn: serverTimestamp(), ultimaAuditoriaId: 's1',
  };
  if (bajaTipo) change.bajaTipo = bajaTipo;
  b.update(doc(db, `usuarios/${uid}`), change);
  return b;
}

test('baja lógica: el trabajador queda inactivo, con motivo y auditoría', async () => {
  await assertSucceeds(
    estadoBatch(as('admin'), 'admin', 'mesero', { estado: 'baja', tipo: 'renuncia', bajaTipo: 'renuncia' }).commit(),
  );
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), 'usuarios/mesero'));
    if (snap.data().activo !== false || snap.data().estado !== 'baja') throw new Error('no quedó de baja');
  });
});

test('la baja exige motivo escrito y tipo coherente', async () => {
  await assertFails(estadoBatch(as('admin'), 'admin', 'mesero', { estado: 'baja', tipo: 'despido', bajaTipo: 'despido', motivo: 'corto' }).commit());
  await assertFails(estadoBatch(as('admin'), 'admin', 'mesero', { estado: 'baja', tipo: 'despido', bajaTipo: 'otro' }).commit());
  await assertFails(estadoBatch(as('admin'), 'admin', 'mesero', { estado: 'suspendido', tipo: 'renuncia', bajaTipo: 'renuncia' }).commit());
});

test('no se puede cambiar el estado sin registrar el movimiento', async () => {
  const db = as('admin');
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/s1'), {
    accion: 'cambiar_estado', actorUid: 'admin', actorNombre: 'X', objetivo: 'mesero', campos: ['estado'], creadoEn: serverTimestamp(),
  });
  b.update(doc(db, 'usuarios/mesero'), {
    estado: 'baja', activo: false, bajaTipo: 'otro', ultimoMovimientoId: 'm1', actualizadoEn: serverTimestamp(), ultimaAuditoriaId: 's1',
  });
  await assertFails(b.commit());
});

test('reactivar a un trabajador de baja exige motivo y queda auditado', async () => {
  await assertSucceeds(estadoBatch(as('admin'), 'admin', 'baja', { estado: 'activo', tipo: 'reactivacion' }).commit());
});

test('admin no da de baja a otro admin; nadie se da de baja a sí mismo', async () => {
  await assertFails(estadoBatch(as('admin'), 'admin', 'admin2', { estado: 'baja', tipo: 'otro', bajaTipo: 'otro' }).commit());
  await assertFails(estadoBatch(as('super'), 'super', 'super', { estado: 'baja', tipo: 'otro', bajaTipo: 'otro' }).commit());
  await assertSucceeds(estadoBatch(as('super'), 'super', 'admin2', { estado: 'suspendido', tipo: 'suspension', bajaTipo: 'suspension' }).commit());
});

test('los motivos confidenciales solo los lee el superadmin', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'movimientosPersonal/x'), { uid: 'mesero', motivo: 'secreto largo' });
  });
  await assertSucceeds(getDoc(doc(as('super'), 'movimientosPersonal/x')));
  await assertFails(getDoc(doc(as('admin'), 'movimientosPersonal/x')));
  await assertFails(getDoc(doc(as('mesero'), 'movimientosPersonal/x')));
});

function restriccionBatch(db, actor, documento, { estado = 'activa', justificacion = 'Justificación suficiente', revisarEn = '2027-01-01' } = {}) {
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/r1'), {
    accion: 'crear_restriccion', actorUid: actor, actorNombre: 'X', objetivo: documento, campos: [], creadoEn: serverTimestamp(),
  });
  b.set(doc(db, `restricciones/${documento}`), {
    estado, establecidaPor: actor, actualizadoEn: serverTimestamp(), revisarEn, ultimaAuditoriaId: 'r1',
  });
  b.set(doc(db, `restricciones/${documento}/privado/detalle`), {
    justificacion, actorUid: actor, actualizadoEn: serverTimestamp(),
  });
  return b;
}

test('solo el superadmin establece restricciones, con justificación y revisión', async () => {
  await assertFails(restriccionBatch(as('admin'), 'admin', '55555555').commit());
  await assertFails(restriccionBatch(as('super'), 'super', '55555555', { justificacion: 'corta' }).commit());
  await assertFails(restriccionBatch(as('super'), 'super', '55555555', { revisarEn: 'mañana' }).commit());
  await assertSucceeds(restriccionBatch(as('super'), 'super', '55555555').commit());
});

test('el admin ve el aviso de restricción pero no su justificación', async () => {
  await restriccionBatch(as('super'), 'super', '55555555').commit();
  await assertSucceeds(getDoc(doc(as('admin'), 'restricciones/55555555')));
  await assertFails(getDoc(doc(as('admin'), 'restricciones/55555555/privado/detalle')));
  await assertSucceeds(getDoc(doc(as('super'), 'restricciones/55555555/privado/detalle')));
});

test('una restricción no bloquea automáticamente una contratación', async () => {
  await restriccionBatch(as('super'), 'super', '77777777').commit();
  await assertSucceeds(altaBatch(as('admin'), 'admin', 'nuevo', { numeroDocumento: '77777777' }).commit());
});

test('la auditoría es append-only y solo la lee el superadmin', async () => {
  await altaBatch(as('admin'), 'admin', 'nuevo').commit();
  await assertSucceeds(getDoc(doc(as('super'), 'auditoria/a1')));
  await assertFails(getDoc(doc(as('admin'), 'auditoria/a1')));
  await assertFails(setDoc(doc(as('admin'), 'auditoria/a1'), { accion: 'x' }));
});

test('no se puede falsear al responsable de la auditoría', async () => {
  const db = as('admin');
  await assertFails(setDoc(doc(db, 'auditoria/falsa'), {
    accion: 'x', actorUid: 'super', actorNombre: 'S', objetivo: 'mesero', campos: [], creadoEn: serverTimestamp(),
  }));
});

test('el superadmin de la Fase 2 (perfil mínimo) lista, da de alta y administra sin migrar', async () => {
  const { getDocs, collection, Timestamp } = require('firebase/firestore');
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'usuarios/legacy'), {
      activo: true, creadoEn: Timestamp.now(), email: 'sprad@granjaazul.com', nombre: 'AdGjAzul', rol: 'superadmin',
    });
  });
  await assertSucceeds(getDocs(collection(as('legacy'), 'usuarios')));
  await assertSucceeds(altaBatch(as('legacy'), 'legacy', 'nuevo', { rol: 'admin' }).commit());
  await assertSucceeds(editBatch(as('legacy'), 'legacy', 'mesero', { celular: '911111111' }, 'e9').commit());
});

// --- Verificación de correo y activación ---

const asUnverified = (uid) => env.authenticatedContext(uid, { email_verified: false }).firestore();

test('con el correo sin verificar no hay acceso a datos, aunque el perfil esté activo', async () => {
  const { getDocs, collection } = require('firebase/firestore');
  await assertFails(getDocs(collection(asUnverified('super'), 'usuarios')));
  await assertFails(altaBatch(asUnverified('admin'), 'admin', 'nuevo').commit());
  await assertFails(getDoc(doc(asUnverified('admin'), 'usuarios/mesero')));
  await assertFails(setDoc(doc(asUnverified('mesero'), `qrTokens/${'a'.repeat(32)}`), {
    uid: 'mesero', tipo: 'entrada', nombreMostrar: 'Mario', creadoEn: serverTimestamp(), usadoEn: null, terminalId: null,
  }));
});

test('sin verificar solo puede leer su propio perfil (para mostrar la pantalla de verificación)', async () => {
  await assertSucceeds(getDoc(doc(asUnverified('mesero'), 'usuarios/mesero')));
  await assertFails(getDoc(doc(asUnverified('mesero'), 'usuarios/admin')));
});

test('activación: el trabajador verificado registra activadoEn una sola vez', async () => {
  const { updateDoc } = require('firebase/firestore');
  await assertSucceeds(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { activadoEn: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { activadoEn: serverTimestamp() }));
});

test('activación: exige correo verificado, hora del servidor y solo ese campo', async () => {
  const { updateDoc, Timestamp } = require('firebase/firestore');
  await assertFails(updateDoc(doc(asUnverified('mesero'), 'usuarios/mesero'), { activadoEn: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { activadoEn: Timestamp.fromMillis(1) }));
  await assertFails(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { activadoEn: serverTimestamp(), rol: 'admin' }));
  await assertFails(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { activadoEn: serverTimestamp(), estado: 'baja' }));
});

test('activación: nadie activa a otro y un inactivo no se activa', async () => {
  const { updateDoc } = require('firebase/firestore');
  await assertFails(updateDoc(doc(as('otro'), 'usuarios/mesero'), { activadoEn: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('admin'), 'usuarios/mesero'), { activadoEn: serverTimestamp() }));
  await assertFails(updateDoc(doc(as('baja'), 'usuarios/baja'), { activadoEn: serverTimestamp() }));
});
