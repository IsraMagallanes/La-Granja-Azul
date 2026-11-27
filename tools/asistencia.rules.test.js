// Reglas de asistencia por QR (genera Superadmin/Admin/Cajero; escanean
// Mesero/Cocina/Cajero), terminales y regularización.
const { test, before, after, beforeEach } = require('node:test');
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, setDoc, getDoc, getDocs, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp } = require('firebase/firestore');
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
    await setDoc(doc(db, 'usuarios/caja'), staff({ nombres: 'Carla', rol: 'cajero', numeroDocumento: '77777771' }));
    await setDoc(doc(db, 'usuarios/caja2'), staff({ nombres: 'Celia', rol: 'cajero', numeroDocumento: '77777772' }));
    await setDoc(doc(db, 'usuarios/baja'), staff({ nombres: 'Bruno', rol: 'cajero', estado: 'baja', activo: false, numeroDocumento: '66666666' }));
    await setDoc(doc(db, 'terminales/term1'), { nombre: 'Tablet cocina', activo: true });
    await setDoc(doc(db, 'terminales/termOff'), { nombre: 'Vieja', activo: false });
    await setDoc(doc(db, 'terminalClaves/term1'), { clave: KEY });
    await setDoc(doc(db, 'terminalClaves/termOff'), { clave: KEY });
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

/** QR de asistencia ya generado (siembra directa, sin pasar por las reglas). */
async function seedQr(id, generadorUid, generadorRol, { ageSeconds = 0, nombre = 'Gema' } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `qrTokens/${id}`), {
      generadorUid, generadorRol, nombreMostrar: nombre,
      creadoEn: Timestamp.fromMillis(Date.now() - ageSeconds * 1000),
    });
  });
}

async function seedOpen(uid, aid = 'asis1') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `asistencias/${aid}`), {
      uid, entrada: Timestamp.fromMillis(Date.now() - 3600_000), salida: null, origen: 'qr',
      tokenId: 'old', regularizada: false,
    });
    await setDoc(doc(db, `estadoAsistencia/${uid}`), { abierta: true, asistenciaId: aid, actualizadoEn: Timestamp.now() });
  });
}

/** Entrada que registra SU PROPIO escáner, en un único lote atómico. */
function scanEntrada(db, uid, tokenId, aid = 'asis1', overrides = {}) {
  const b = writeBatch(db);
  b.set(doc(db, `asistencias/${aid}`), {
    uid, entrada: serverTimestamp(), salida: null, origen: 'qr', tokenId, regularizada: false, ...overrides,
  });
  b.set(doc(db, `estadoAsistencia/${uid}`), { abierta: true, asistenciaId: aid, actualizadoEn: serverTimestamp(), tokenId });
  return b;
}

function scanSalida(db, uid, tokenId, aid = 'asis1') {
  const b = writeBatch(db);
  b.update(doc(db, `asistencias/${aid}`), { salida: serverTimestamp(), salidaTokenId: tokenId });
  b.set(doc(db, `estadoAsistencia/${uid}`), { abierta: false, asistenciaId: aid, actualizadoEn: serverTimestamp(), tokenId });
  return b;
}

/** Lote del flujo anterior (la terminal consumía el QR del trabajador). Ya no existe. */
function legacyTerminalBatch(db, terminal, uid, tokenId, aid = 'asis1', clave = KEY) {
  const b = writeBatch(db);
  addProof(b, db, terminal, clave);
  b.update(doc(db, `qrTokens/${tokenId}`), { usadoEn: serverTimestamp(), terminalId: terminal });
  b.set(doc(db, `asistencias/${aid}`), {
    uid, entrada: serverTimestamp(), salida: null, origen: 'qr', terminalId: terminal, tokenId, regularizada: false,
  });
  b.set(doc(db, `estadoAsistencia/${uid}`), { abierta: true, asistenciaId: aid, actualizadoEn: serverTimestamp() });
  return b;
}

const newToken = (uid, rol, extra = {}) => ({
  generadorUid: uid, generadorRol: rol, nombreMostrar: 'Gema', creadoEn: serverTimestamp(), ...extra,
});

// --- Generación del QR: solo Superadmin, Admin y Cajero ---

test('Superadmin, Admin y Cajero generan el QR sin registrar asistencia de nadie', async () => {
  for (const [uid, rol, nombre] of [['super', 'superadmin', 'Sofia'], ['admin', 'admin', 'Adan'], ['caja', 'cajero', 'Carla']]) {
    await assertSucceeds(setDoc(doc(as(uid), `qrTokens/${{ super: '1', admin: '2', caja: '3' }[uid].repeat(32)}`), newToken(uid, rol, { nombreMostrar: nombre })));
  }
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const uid of ['super', 'admin', 'caja']) {
      if ((await getDoc(doc(ctx.firestore(), `estadoAsistencia/${uid}`))).exists()) {
        throw new Error('generar el QR no debe registrar asistencia');
      }
    }
  });
});

test('Mesero, Cocina y cuentas inactivas NO generan QR', async () => {
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('mesero', 'mesero', { nombreMostrar: 'Mario' })));
  await assertFails(setDoc(doc(as('otro'), `qrTokens/${TOKEN}`), newToken('otro', 'cocina', { nombreMostrar: 'Olga' })));
  // Aunque se hagan pasar por un rol que genera.
  await assertFails(setDoc(doc(as('mesero'), `qrTokens/${TOKEN}`), newToken('mesero', 'admin', { nombreMostrar: 'Mario' })));
  await assertFails(setDoc(doc(as('otro'), `qrTokens/${TOKEN}`), newToken('otro', 'cajero', { nombreMostrar: 'Olga' })));
  await assertFails(setDoc(doc(as('baja'), `qrTokens/${TOKEN}`), newToken('baja', 'cajero', { nombreMostrar: 'Bruno' })));
});

test('el QR no se genera a nombre de otro, con otro rol, con datos extra ni con hora falsa', async () => {
  const db = as('caja');
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('admin', 'cajero', { nombreMostrar: 'Carla' })));
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('caja', 'admin', { nombreMostrar: 'Carla' })));
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('caja', 'cajero', { nombreMostrar: 'Otra' })));
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('caja', 'cajero', { nombreMostrar: 'Carla', dni: '1' })));
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('caja', 'cajero', { nombreMostrar: 'Carla', usadoEn: null })));
  await assertFails(setDoc(doc(db, `qrTokens/${TOKEN}`), newToken('caja', 'cajero', { nombreMostrar: 'Carla', creadoEn: Timestamp.fromMillis(Date.now() + 3600_000) })));
  await assertFails(setDoc(doc(db, 'qrTokens/corto'), newToken('caja', 'cajero', { nombreMostrar: 'Carla' })));
});

test('el QR es inmutable y solo se lee por id', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await assertFails(updateDoc(doc(as('admin'), `qrTokens/${TOKEN}`), { creadoEn: serverTimestamp() }));
  await assertFails(deleteDoc(doc(as('admin'), `qrTokens/${TOKEN}`)));
  await assertSucceeds(getDoc(doc(as('mesero'), `qrTokens/${TOKEN}`)));
  await assertFails(getDocs(collection(as('mesero'), 'qrTokens')));
  await assertFails(getDoc(doc(as('term1'), `qrTokens/${TOKEN}`)));
});

// --- Escaneo: Mesero, Cocina y Cajero registran SU entrada y salida ---

test('el Mesero escanea el QR de Admin y registra su entrada con la hora del servidor', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await assertSucceeds(scanEntrada(as('mesero'), 'mesero', TOKEN).commit());
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = (await getDoc(doc(ctx.firestore(), 'asistencias/asis1'))).data();
    if (Math.abs(d.entrada.toMillis() - Date.now()) > 60_000) throw new Error('hora no es la del servidor');
    if (d.salida !== null) throw new Error('salida debería ser nula');
    if (d.uid !== 'mesero') throw new Error('el registro es de quien escanea');
  });
});

test('Mesero y Cocina escanean QR de Superadmin, Admin y Cajero', async () => {
  const generators = [['super', 'superadmin'], ['admin', 'admin'], ['caja', 'cajero']];
  for (const scanner of ['mesero', 'otro']) {
    for (const [uid, rol] of generators) {
      await env.clearFirestore();
      await env.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, 'usuarios/super'), staff({ nombres: 'Sofia', rol: 'superadmin', numeroDocumento: '11111111' }));
        await setDoc(doc(db, 'usuarios/admin'), staff({ nombres: 'Adan', rol: 'admin', numeroDocumento: '22222222' }));
        await setDoc(doc(db, 'usuarios/caja'), staff({ nombres: 'Carla', rol: 'cajero', numeroDocumento: '77777771' }));
        await setDoc(doc(db, 'usuarios/mesero'), staff({ nombres: 'Mario', rol: 'mesero', numeroDocumento: '44444444' }));
        await setDoc(doc(db, 'usuarios/otro'), staff({ nombres: 'Olga', rol: 'cocina', numeroDocumento: '55555555' }));
      });
      await seedQr(TOKEN, uid, rol);
      await assertSucceeds(scanEntrada(as(scanner), scanner, TOKEN).commit());
    }
  }
});

test('el Cajero solo escanea QR de Admin o Superadmin', async () => {
  await seedQr(TOKEN, 'caja2', 'cajero');
  await assertFails(scanEntrada(as('caja'), 'caja', TOKEN).commit());
  await seedQr(TOKEN2, 'admin', 'admin');
  await assertSucceeds(scanEntrada(as('caja'), 'caja', TOKEN2).commit());
});

test('el Cajero también puede escanear un QR de Superadmin', async () => {
  await seedQr(TOKEN, 'super', 'superadmin');
  await assertSucceeds(scanEntrada(as('caja'), 'caja', TOKEN).commit());
});

test('Admin y Superadmin no registran asistencia por QR', async () => {
  await seedQr(TOKEN, 'caja', 'cajero');
  await assertFails(scanEntrada(as('admin'), 'admin', TOKEN).commit());
  await assertFails(scanEntrada(as('super'), 'super', TOKEN).commit());
});

test('nadie escanea su propio QR', async () => {
  await seedQr(TOKEN, 'caja', 'cajero');
  await assertFails(scanEntrada(as('caja'), 'caja', TOKEN).commit());
});

test('un QR inexistente, vencido o de un generador dado de baja se rechaza', async () => {
  await assertFails(scanEntrada(as('mesero'), 'mesero', TOKEN).commit());
  await seedQr(TOKEN, 'admin', 'admin', { ageSeconds: 120 });
  await assertFails(scanEntrada(as('mesero'), 'mesero', TOKEN).commit());
  // El rol del QR debe seguir siendo el actual del generador.
  await seedQr(TOKEN2, 'mesero', 'admin');
  await assertFails(scanEntrada(as('otro'), 'otro', TOKEN2).commit());
  await seedQr('c'.repeat(32), 'baja', 'cajero');
  await assertFails(scanEntrada(as('mesero'), 'mesero', 'c'.repeat(32)).commit());
});

test('el QR no registra la asistencia de otra persona', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await assertFails(scanEntrada(as('mesero'), 'otro', TOKEN).commit());
  await assertFails(scanEntrada(as('admin'), 'otro', TOKEN).commit());
});

test('un trabajador dado de baja no puede marcar', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await assertFails(scanEntrada(as('baja'), 'baja', TOKEN).commit());
});

test('no se aceptan entradas duplicadas', async () => {
  await seedOpen('mesero');
  await seedQr(TOKEN, 'admin', 'admin');
  await assertFails(scanEntrada(as('mesero'), 'mesero', TOKEN, 'asis2').commit());
});

test('no hay salida sin entrada', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  const db = as('mesero');
  await assertFails(scanEntrada(db, 'mesero', TOKEN, 'falsa', { salida: serverTimestamp() }).commit());
  await assertFails(scanSalida(db, 'mesero', TOKEN, 'inexistente').commit());
});

test('la salida cierra la jornada abierta y no se repite', async () => {
  await seedOpen('mesero');
  await seedQr(TOKEN, 'admin', 'admin');
  await assertSucceeds(scanSalida(as('mesero'), 'mesero', TOKEN).commit());
  await seedQr(TOKEN2, 'admin', 'admin');
  await assertFails(scanSalida(as('mesero'), 'mesero', TOKEN2).commit());
});

test('la salida solo la registra el dueño del registro y con su propio QR vigente', async () => {
  await seedOpen('mesero');
  await seedQr(TOKEN, 'admin', 'admin');
  await assertFails(scanSalida(as('otro'), 'mesero', TOKEN).commit());
  await seedQr(TOKEN2, 'admin', 'admin', { ageSeconds: 120 });
  await assertFails(scanSalida(as('mesero'), 'mesero', TOKEN2).commit());
});

test('un mismo QR no encadena dos marcaciones del mismo trabajador', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await seedQr(TOKEN2, 'admin', 'admin');
  await assertSucceeds(scanEntrada(as('mesero'), 'mesero', TOKEN).commit());
  await assertFails(scanSalida(as('mesero'), 'mesero', TOKEN).commit());
  await assertSucceeds(scanSalida(as('mesero'), 'mesero', TOKEN2).commit());
});

test('varias personas pueden escanear el mismo QR vigente', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  await assertSucceeds(scanEntrada(as('mesero'), 'mesero', TOKEN, 'asisM').commit());
  await assertSucceeds(scanEntrada(as('otro'), 'otro', TOKEN, 'asisO').commit());
});

test('la hora y los campos no pueden ser falseados', async () => {
  await seedQr(TOKEN, 'admin', 'admin');
  const db = as('mesero');
  await assertFails(scanEntrada(db, 'mesero', TOKEN, 'asis1', { entrada: Timestamp.fromMillis(Date.now() - 3 * 3600_000) }).commit());
  await assertFails(scanEntrada(db, 'mesero', TOKEN, 'asis1', { terminalId: 'term1' }).commit());
  await assertFails(scanEntrada(db, 'mesero', TOKEN, 'asis1', { origen: 'regularizada' }).commit());
  await assertFails(scanEntrada(db, 'mesero', TOKEN, 'asis1', { regularizada: true }).commit());
});

test('no se marca sin escanear un QR ni con el estado desajustado', async () => {
  const db = as('mesero');
  await assertFails(setDoc(doc(db, 'asistencias/x'), {
    uid: 'mesero', entrada: serverTimestamp(), salida: null, origen: 'qr', tokenId: TOKEN, regularizada: false,
  }));
  await assertFails(setDoc(doc(db, 'estadoAsistencia/mesero'), { abierta: true, asistenciaId: 'x', actualizadoEn: serverTimestamp(), tokenId: TOKEN }));
  // Con un QR válido, el estado debe corresponder al registro creado en el mismo lote.
  await seedQr(TOKEN, 'admin', 'admin');
  const b = writeBatch(db);
  b.set(doc(db, 'asistencias/asis1'), { uid: 'mesero', entrada: serverTimestamp(), salida: null, origen: 'qr', tokenId: TOKEN, regularizada: false });
  b.set(doc(db, 'estadoAsistencia/mesero'), { abierta: true, asistenciaId: 'otra', actualizadoEn: serverTimestamp(), tokenId: TOKEN });
  await assertFails(b.commit());
});

// --- Sistema antiguo de terminales: retirado ---

const OLD_COLLECTIONS = ['terminales', 'terminalClaves', 'terminalPruebas', 'solicitudesEliminacionTerminal'];

test('las colecciones del sistema antiguo de terminales están cerradas a todos los clientes', async () => {
  for (const uid of ['super', 'admin', 'mesero', 'caja', 'term1']) {
    for (const col of OLD_COLLECTIONS) {
      const db = as(uid);
      await assertFails(getDoc(doc(db, `${col}/${uid === 'term1' ? 'term1' : 'x'}`)));
      await assertFails(getDocs(collection(db, col)));
      await assertFails(setDoc(doc(db, `${col}/${uid}`), { nombre: 'Tablet', activo: true }));
      await assertFails(deleteDoc(doc(db, `${col}/term1`)));
    }
  }
});

test('una cuenta de terminal que aún exista no registra asistencia, no genera QR y no lee nada', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `qrTokens/${TOKEN}`), {
      uid: 'mesero', tipo: 'entrada', nombreMostrar: 'Mario', creadoEn: Timestamp.now(), usadoEn: null, terminalId: null,
    });
  });
  await assertFails(legacyTerminalBatch(as('term1'), 'term1', 'mesero', TOKEN).commit());
  await assertFails(legacyTerminalBatch(as('termOff'), 'termOff', 'mesero', TOKEN).commit());
  await assertFails(setDoc(doc(as('term1'), `qrTokens/${TOKEN2}`), newToken('term1', 'admin', { nombreMostrar: 'Tablet' })));
  await seedOpen('mesero');
  await assertFails(getDoc(doc(as('term1'), 'usuarios/mesero')));
  await assertFails(getDoc(doc(as('term1'), 'estadoAsistencia/mesero')));
  await assertFails(getDoc(doc(as('term1'), 'asistencias/asis1')));
  await assertFails(scanSalida(as('term1'), 'mesero', TOKEN2, 'asis1').commit());
});

test('un perfil de personal sí puede crearse con cualquier UID: ya no hay cuentas de terminal reservadas', async () => {
  const db = as('admin');
  const data = staff({ nombres: 'Nuevo', numeroDocumento: '77777777', rol: 'mesero' });
  const b = writeBatch(db);
  b.set(doc(db, 'auditoria/z1'), { accion: 'crear_trabajador', actorUid: 'admin', actorNombre: 'X', objetivo: 'nuevo1', campos: [], creadoEn: serverTimestamp() });
  b.set(doc(db, 'usuarios/nuevo1'), { ...data, ultimaAuditoriaId: 'z1', creadoEn: serverTimestamp(), creadoPor: 'admin', actualizadoEn: serverTimestamp() });
  b.set(doc(db, 'documentos/77777777'), { uid: 'nuevo1', creadoEn: serverTimestamp() });
  b.set(doc(db, `correos/${data.email}`), { uid: 'nuevo1', creadoEn: serverTimestamp() });
  await assertSucceeds(b.commit());
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
