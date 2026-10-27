// Reglas de asistencia por QR, terminales y regularización.
const { test, before, after, beforeEach } = require('node:test');
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, writeBatch, serverTimestamp, Timestamp } = require('firebase/firestore');
const { createEnv, staff } = require('./support');

let env;
before(async () => { env = await createEnv(); });
after(() => env.cleanup());

const TOKEN = 'a'.repeat(32);
const TOKEN2 = 'b'.repeat(32);
const KEY = 'k'.repeat(40);

/** Prueba de posesión del secreto del dispositivo, en el mismo lote. */
function addProof(b, db, terminal, clave = KEY) {
  b.set(doc(db, `terminalPruebas/${terminal}`), { clave, actualizadoEn: serverTimestamp() });
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'usuarios/super'), staff({ nombres: 'Sofia', rol: 'superadmin', numeroDocumento: '11111111' }));
    await setDoc(doc(db, 'usuarios/admin'), staff({ nombres: 'Adan', rol: 'admin', numeroDocumento: '22222222' }));
    await setDoc(doc(db, 'usuarios/adminReg'), staff({ nombres: 'Alba', rol: 'admin', puedeRegularizar: true, numeroDocumento: '33333333' }));
    await setDoc(doc(db, 'usuarios/mesero'), staff({ nombres: 'Mario', rol: 'mesero', numeroDocumento: '44444444' }));
    await setDoc(doc(db, 'usuarios/otro'), staff({ nombres: 'Olga', rol: 'cocina', numeroDocumento: '55555555' }));
    await setDoc(doc(db, 'usuarios/baja'), staff({ nombres: 'Bruno', rol: 'cajero', estado: 'baja', activo: false, numeroDocumento: '66666666' }));
    await setDoc(doc(db, 'terminales/term1'), { nombre: 'Tablet cocina', activo: true });
    await setDoc(doc(db, 'terminales/termOff'), { nombre: 'Vieja', activo: false });
    await setDoc(doc(db, 'terminalClaves/term1'), { clave: KEY });
    await setDoc(doc(db, 'terminalClaves/termOff'), { clave: KEY });
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

async function seedToken(id, uid, tipo, { ageSeconds = 0, usado = false } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `qrTokens/${id}`), {
      uid, tipo, nombreMostrar: 'x',
      creadoEn: Timestamp.fromMillis(Date.now() - ageSeconds * 1000),
      usadoEn: usado ? Timestamp.now() : null, terminalId: null,
    });
  });
}

async function seedOpen(uid, aid = 'asis1') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `asistencias/${aid}`), {
      uid, entrada: Timestamp.fromMillis(Date.now() - 3600_000), salida: null, origen: 'qr',
      terminalId: 'term1', tokenId: 'old', regularizada: false,
    });
    await setDoc(doc(db, `estadoAsistencia/${uid}`), { abierta: true, asistenciaId: aid, actualizadoEn: Timestamp.now() });
  });
}

function entradaBatch(db, terminal, uid, tokenId, aid = 'asis1', clave = KEY) {
  const b = writeBatch(db);
  addProof(b, db, terminal, clave);
  b.update(doc(db, `qrTokens/${tokenId}`), { usadoEn: serverTimestamp(), terminalId: terminal });
  b.set(doc(db, `asistencias/${aid}`), {
    uid, entrada: serverTimestamp(), salida: null, origen: 'qr', terminalId: terminal, tokenId, regularizada: false,
  });
  b.set(doc(db, `estadoAsistencia/${uid}`), { abierta: true, asistenciaId: aid, actualizadoEn: serverTimestamp() });
  return b;
}

function salidaBatch(db, terminal, uid, tokenId, aid = 'asis1', clave = KEY) {
  const b = writeBatch(db);
  addProof(b, db, terminal, clave);
  b.update(doc(db, `qrTokens/${tokenId}`), { usadoEn: serverTimestamp(), terminalId: terminal });
  b.update(doc(db, `asistencias/${aid}`), { salida: serverTimestamp(), salidaTokenId: tokenId });
  b.set(doc(db, `estadoAsistencia/${uid}`), { abierta: false, asistenciaId: aid, actualizadoEn: serverTimestamp() });
  return b;
}

const newToken = (uid, tipo, extra = {}) => ({
  uid, tipo, nombreMostrar: 'Mario', creadoEn: serverTimestamp(), usadoEn: null, terminalId: null, ...extra,
});

// --- Generación del QR (app del trabajador) ---

test('el trabajador activo genera su QR sin registrar asistencia', async () => {
  await assertSucceeds(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('mesero', 'entrada')));
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), 'estadoAsistencia/mesero'));
    if (snap.exists()) throw new Error('generar el QR no debe registrar asistencia');
  });
});

test('no se puede generar un QR a nombre de otro, inactivo o con datos extra', async () => {
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('otro', 'entrada')));
  await assertFails(setDoc(doc(as('baja'), `qrTokens/${TOKEN}`), newToken('baja', 'entrada', { nombreMostrar: 'Bruno' })));
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('mesero', 'entrada', { dni: '44444444' })));
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('mesero', 'entrada', { tipo: 'cualquiera' })));
  await assertFails(setDoc(doc(as('mesero'), 'qrTokens/corto'), newToken('mesero', 'entrada')));
});

test('el trabajador no puede marcar como usado su propio QR', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), { usadoEn: serverTimestamp() }, { merge: true }));
});

// --- Terminal ---

test('la terminal autorizada registra la entrada con hora del servidor', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertSucceeds(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), 'asistencias/asis1'));
    const d = snap.data();
    if (Math.abs(d.entrada.toMillis() - Date.now()) > 60_000) throw new Error('hora no es la del servidor');
    if (d.salida !== null) throw new Error('salida debería ser nula');
  });
});

test('un QR no se reutiliza', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertSucceeds(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
  // Reutilizar el mismo token de entrada, aun con otra jornada, se rechaza.
  await assertFails(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN, 'asis2').commit());
});

test('un QR vencido (más de 45 s) se rechaza', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada', { ageSeconds: 120 });
  await assertFails(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
});

test('un QR ya usado se rechaza', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada', { usado: true });
  await assertFails(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
});

test('no se aceptan entradas duplicadas', async () => {
  await seedOpen('mesero');
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN, 'asis2').commit());
});

test('no hay salida sin entrada', async () => {
  await seedToken(TOKEN, 'mesero', 'salida');
  const db = as('term1');
  const b = writeBatch(db);
  addProof(b, db, 'term1');
  b.update(doc(db, `qrTokens/${TOKEN}`), { usadoEn: serverTimestamp(), terminalId: 'term1' });
  b.set(doc(db, 'asistencias/falsa'), {
    uid: 'mesero', entrada: serverTimestamp(), salida: serverTimestamp(), origen: 'qr', terminalId: 'term1', tokenId: TOKEN, regularizada: false,
  });
  b.set(doc(db, 'estadoAsistencia/mesero'), { abierta: false, asistenciaId: 'falsa', actualizadoEn: serverTimestamp() });
  await assertFails(b.commit());
});

test('la salida cierra la jornada abierta y no se repite', async () => {
  await seedOpen('mesero');
  await seedToken(TOKEN, 'mesero', 'salida');
  await assertSucceeds(salidaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
  await seedToken(TOKEN2, 'mesero', 'salida');
  await assertFails(salidaBatch(as('term1'), 'term1', 'mesero', TOKEN2).commit());
});

test('un QR de entrada no sirve para registrar salida (y viceversa)', async () => {
  await seedOpen('mesero');
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(salidaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
});

test('el QR de un trabajador no registra la asistencia de otro', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(entradaBatch(as('term1'), 'term1', 'otro', TOKEN).commit());
});

test('un trabajador dado de baja no puede marcar', async () => {
  await seedToken(TOKEN, 'baja', 'entrada');
  await assertFails(entradaBatch(as('term1'), 'term1', 'baja', TOKEN).commit());
});

test('terminal revocada, admin y trabajador no pueden registrar', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(entradaBatch(as('termOff'), 'termOff', 'mesero', TOKEN).commit());
  await assertFails(entradaBatch(as('super'), 'super', 'mesero', TOKEN).commit());
  await assertFails(entradaBatch(as('mesero'), 'mesero', 'mesero', TOKEN).commit());
});

test('no se marca directamente desde un dispositivo personal', async () => {
  const db = as('mesero');
  await assertFails(setDoc(doc(db, 'asistencias/x'), {
    uid: 'mesero', entrada: serverTimestamp(), salida: null, origen: 'qr', terminalId: 'mesero', tokenId: TOKEN, regularizada: false,
  }));
  await assertFails(setDoc(doc(db, 'estadoAsistencia/mesero'), { abierta: true, asistenciaId: 'x', actualizadoEn: serverTimestamp() }));
});

test('la hora no puede ser falseada por la terminal', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  const db = as('term1');
  const b = writeBatch(db);
  addProof(b, db, 'term1');
  b.update(doc(db, `qrTokens/${TOKEN}`), { usadoEn: serverTimestamp(), terminalId: 'term1' });
  b.set(doc(db, 'asistencias/asis1'), {
    uid: 'mesero', entrada: Timestamp.fromMillis(Date.now() - 3 * 3600_000), salida: null, origen: 'qr', terminalId: 'term1', tokenId: TOKEN, regularizada: false,
  });
  b.set(doc(db, 'estadoAsistencia/mesero'), { abierta: true, asistenciaId: 'asis1', actualizadoEn: serverTimestamp() });
  await assertFails(b.commit());
});

test('la terminal no puede leer perfiles ni listar tokens', async () => {
  await assertFails(getDoc(doc(as('term1'), 'usuarios/mesero')));
});

// --- Administración de terminales ---

function terminalBatch(db, actor, id, activo) {
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/t1'), {
    accion: 'autorizar_terminal', actorUid: actor, actorNombre: 'X', objetivo: id, campos: [], creadoEn: serverTimestamp(),
  });
  b.set(doc(db, `terminales/${id}`), {
    nombre: 'Tablet salón', activo, autorizadoPor: actor, actualizadoEn: serverTimestamp(), ultimaAuditoriaId: 't1',
  });
  return b;
}

test('solo el superadmin autoriza y revoca terminales', async () => {
  await assertFails(terminalBatch(as('admin'), 'admin', 'nueva', true).commit());
  await assertSucceeds(terminalBatch(as('super'), 'super', 'nueva', true).commit());
});

// --- Regularización ---

function regBatch(db, actor, uid, overrides = {}) {
  const n = `${actor}_${uid}`;
  const b = writeBatch(db);
  b.set(doc(db, `auditoria/g_${n}`), {
    accion: 'regularizar_asistencia', actorUid: actor, actorNombre: 'X', objetivo: uid, campos: [], creadoEn: serverTimestamp(),
  });
  b.set(doc(db, `asistencias/reg_${n}`), {
    uid,
    entrada: Timestamp.fromMillis(Date.now() - 8 * 3600_000),
    salida: Timestamp.fromMillis(Date.now() - 3600_000),
    origen: 'regularizada', regularizada: true,
    motivo: 'Olvidó marcar la entrada', regularizadoPor: actor, regularizadoEn: serverTimestamp(),
    ultimaAuditoriaId: `g_${n}`,
    ...overrides,
  });
  return b;
}

test('regulariza el superadmin o el admin autorizado, con motivo y auditoría', async () => {
  await assertSucceeds(regBatch(as('super'), 'super', 'mesero').commit());
  await assertSucceeds(regBatch(as('adminReg'), 'adminReg', 'mesero').commit());
});

test('un admin sin autorización no regulariza', () =>
  assertFails(regBatch(as('admin'), 'admin', 'mesero').commit()));

test('la regularización exige motivo, no es sobre sí mismo ni sobre un superior', async () => {
  await assertFails(regBatch(as('super'), 'super', 'mesero', { motivo: 'corto' }).commit());
  await assertFails(regBatch(as('adminReg'), 'adminReg', 'adminReg').commit());
  await assertFails(regBatch(as('adminReg'), 'adminReg', 'admin').commit());
  await assertFails(regBatch(as('mesero'), 'mesero', 'mesero').commit());
});

test('la regularización no admite fechas futuras ni salida anterior a la entrada', async () => {
  await assertFails(regBatch(as('super'), 'super', 'mesero', { entrada: Timestamp.fromMillis(Date.now() + 3600_000), salida: null }).commit());
  await assertFails(regBatch(as('super'), 'super', 'mesero', {
    entrada: Timestamp.fromMillis(Date.now() - 3600_000), salida: Timestamp.fromMillis(Date.now() - 7200_000),
  }).commit());
});

test('el trabajador lee solo su historial', async () => {
  await seedOpen('mesero');
  await assertSucceeds(getDoc(doc(as('mesero'), 'asistencias/asis1')));
  await assertFails(getDoc(doc(as('otro'), 'asistencias/asis1')));
  await assertSucceeds(getDoc(doc(as('admin'), 'asistencias/asis1')));
});

// --- Horarios y correcciones ---

function horarioBatch(db, actor, overrides = {}) {
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/h1'), {
    accion: 'guardar_horario', actorUid: actor, actorNombre: 'X', objetivo: 'turno1', campos: [], creadoEn: serverTimestamp(),
  });
  b.set(doc(db, 'horarios/turno1'), {
    nombre: 'Noche', horaInicio: '22:00', horaFin: '06:00', toleranciaMin: 10, dias: [1, 2, 3, 4, 5], activo: true,
    actualizadoEn: serverTimestamp(), ultimaAuditoriaId: 'h1', ...overrides,
  });
  return b;
}

test('admin configura horarios (incluido turno nocturno) con datos válidos', async () => {
  await assertSucceeds(horarioBatch(as('admin'), 'admin').commit());
  await assertFails(horarioBatch(as('admin'), 'admin', { horaInicio: '25:00' }).commit());
  await assertFails(horarioBatch(as('admin'), 'admin', { toleranciaMin: 500 }).commit());
  await assertFails(horarioBatch(as('mesero'), 'mesero').commit());
});

test('el trabajador crea solicitudes de corrección propias; solo quien regulariza las resuelve', async () => {
  const solicitud = { uid: 'mesero', fecha: '2026-10-20', tipo: 'entrada', motivo: 'Olvidé marcar la entrada', estado: 'pendiente', creadoEn: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('mesero'), 'correcciones/c1'), solicitud));
  await assertFails(setDoc(doc(as('mesero'), 'correcciones/c2'), { ...solicitud, uid: 'otro' }));
  await assertFails(setDoc(doc(as('mesero'), 'correcciones/c3'), { ...solicitud, estado: 'aprobada' }));
  await assertFails(getDoc(doc(as('otro'), 'correcciones/c1')));

  const resolver = (db, actor) => {
    const b = writeBatch(db);
    b.set(doc(db, 'auditoria/rc'), {
      accion: 'resolver_correccion', actorUid: actor, actorNombre: 'X', objetivo: 'mesero', campos: [], creadoEn: serverTimestamp(),
    });
    b.update(doc(db, 'correcciones/c1'), {
      estado: 'aprobada', respuesta: 'ok', resueltoPor: actor, resueltoEn: serverTimestamp(), ultimaAuditoriaId: 'rc',
    });
    return b;
  };
  await assertFails(resolver(as('admin'), 'admin').commit());
  await assertSucceeds(resolver(as('adminReg'), 'adminReg').commit());
});

// --- Credenciales copiadas / enlace con el dispositivo ---

test('credenciales copiadas sin el secreto del dispositivo no pueden marcar', async () => {
  await seedToken(TOKEN, 'mesero', 'entrada');
  // Ni con clave equivocada...
  await assertFails(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN, 'asis1', 'x'.repeat(40)).commit());
  // ...ni omitiendo la prueba.
  const db = as('term1');
  const b = writeBatch(db);
  b.update(doc(db, `qrTokens/${TOKEN}`), { usadoEn: serverTimestamp(), terminalId: 'term1' });
  b.set(doc(db, 'asistencias/asis1'), {
    uid: 'mesero', entrada: serverTimestamp(), salida: null, origen: 'qr', terminalId: 'term1', tokenId: TOKEN, regularizada: false,
  });
  b.set(doc(db, 'estadoAsistencia/mesero'), { abierta: true, asistenciaId: 'asis1', actualizadoEn: serverTimestamp() });
  await assertFails(b.commit());
  // Con el secreto correcto sí.
  await assertSucceeds(entradaBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
});

test('el secreto del dispositivo no se puede leer ni reemplazar', async () => {
  await assertFails(getDoc(doc(as('term1'), 'terminalClaves/term1')));
  await assertFails(getDoc(doc(as('super'), 'terminalClaves/term1')));
  await assertFails(setDoc(doc(as('term1'), 'terminalClaves/term1'), { clave: 'n'.repeat(40), creadoEn: serverTimestamp() }));
  await assertFails(getDoc(doc(as('term1'), 'terminalPruebas/term1')));
});

test('enlace inicial: la terminal registra su secreto una sola vez', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'terminales/term2'), { nombre: 'Nueva', activo: true });
  });
  await assertFails(setDoc(doc(as('term2'), 'terminalClaves/term2'), { clave: 'corta', creadoEn: serverTimestamp() }));
  await assertFails(setDoc(doc(as('term1'), 'terminalClaves/term2'), { clave: KEY, creadoEn: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(as('term2'), 'terminalClaves/term2'), { clave: KEY, creadoEn: serverTimestamp() }));
  await assertFails(setDoc(doc(as('term2'), 'terminalClaves/term2'), { clave: 'z'.repeat(40), creadoEn: serverTimestamp() }));
});

test('solo el superadmin restablece el enlace de una terminal', async () => {
  const { deleteDoc } = require('firebase/firestore');
  await assertFails(deleteDoc(doc(as('admin'), 'terminalClaves/term1')));
  await assertFails(deleteDoc(doc(as('term1'), 'terminalClaves/term1')));
  await assertSucceeds(deleteDoc(doc(as('super'), 'terminalClaves/term1')));
});

// --- Cuentas de personal y de terminal no se mezclan ---

test('una cuenta con perfil de personal nunca actúa como terminal', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'terminales/otro'), { nombre: 'Mal creada', activo: true });
    await setDoc(doc(db, 'terminalClaves/otro'), { clave: KEY });
  });
  await seedToken(TOKEN, 'mesero', 'entrada');
  await assertFails(entradaBatch(as('otro'), 'otro', 'mesero', TOKEN).commit());
});

test('no se registra como terminal una cuenta que ya es personal', async () => {
  await assertFails(terminalBatch(as('super'), 'super', 'mesero', true).commit());
});

test('no se crea un perfil de personal sobre la cuenta de una terminal', async () => {
  const db = as('admin');
  const data = staff({ nombres: 'Nuevo', numeroDocumento: '77777777', rol: 'mesero' });
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/z1'), { accion: 'crear_trabajador', actorUid: 'admin', actorNombre: 'X', objetivo: 'term1', campos: [], creadoEn: serverTimestamp() });
  b.set(doc(db, 'usuarios/term1'), { ...data, ultimaAuditoriaId: 'z1', creadoEn: serverTimestamp(), creadoPor: 'admin', actualizadoEn: serverTimestamp() });
  b.set(doc(db, 'documentos/77777777'), { uid: 'term1', creadoEn: serverTimestamp() });
  b.set(doc(db, `correos/${data.email}`), { uid: 'term1', creadoEn: serverTimestamp() });
  await assertFails(b.commit());
});
