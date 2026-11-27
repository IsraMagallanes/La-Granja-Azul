/**
 * Retiro de la CUENTA de Authentication de una antigua terminal, sin eliminar la
 * terminal. A diferencia de `terminal_deletion.js` (que elimina la terminal por
 * completo), aquí `terminales/{uid}` se CONSERVA siempre, con su nombre e
 * historial, porque la tablet física sigue en uso con la cuenta de Caja.
 *
 * Elimina:   la cuenta de Authentication, `terminalClaves/{uid}` y
 *            `terminalPruebas/{uid}` (el secreto de enlace con la tablet pierde
 *            sentido sin la cuenta), y `solicitudesEliminacionTerminal/{uid}`.
 * Conserva:  `terminales/{uid}`, `asistencias`, `auditoria` y TODOS los
 *            `qrTokens` (usados y sin usar: no se purga ninguno aquí).
 *
 * Marca opcional (`marcarRetirada`): solo para una terminal que se retira del
 * todo. Deja el documento como `activo: false, retirada: true` (no lo borra).
 * Una terminal que migra a Caja NO se marca y su documento no se modifica.
 *
 * Solo actúa sobre cuentas que cumplen los cuatro criterios de
 * `terminal_criteria.js`; cualquier cuenta normal queda bloqueada.
 *
 * Orden y reanudación: primero la cuenta de Authentication y después, en un
 * único lote atómico, los documentos y la entrada de auditoría. Repetir el
 * comando completa lo que falte y no duplica la auditoría.
 */
const { COLLECTIONS: CRITERIA_COLLECTIONS, checkExclusivity, countWhere } =
  require('./terminal_criteria');
const { State, TerminalDeletionError, assertValidUid } = require('./terminal_deletion');

const COLLECTIONS = {
  ...CRITERIA_COLLECTIONS,
  claves: 'terminalClaves',
  pruebas: 'terminalPruebas',
  tokens: 'qrTokens',
  solicitudes: 'solicitudesEliminacionTerminal',
};

const AUDIT_ACTION = 'retirar_cuenta_terminal';
const AUDIT_ACTOR_UID = 'script-local';
const AUDIT_ACTOR_NAME = 'Script administrativo local';

async function findAuthUser(auth, uid) {
  try {
    return await auth.getUser(uid);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

function emptyProgress() {
  return { cuentaAuth: false, documentos: false };
}

/** Lee el estado actual sin modificar nada (modo simulación y comprobación previa). */
async function inspectRetirement({ auth, db, uid, marcarRetirada = false }) {
  assertValidUid(uid);
  const authUser = await findAuthUser(auth, uid);
  const [check, claveSnap, pruebaSnap, solicitudSnap] = await Promise.all([
    checkExclusivity({ db, uid, email: authUser?.email }),
    db.collection(COLLECTIONS.claves).doc(uid).get(),
    db.collection(COLLECTIONS.pruebas).doc(uid).get(),
    db.collection(COLLECTIONS.solicitudes).doc(uid).get(),
  ]);
  const [asistencias, auditoria, tokens] = await Promise.all([
    countWhere(db, COLLECTIONS.asistencias, 'terminalId', uid),
    countWhere(db, COLLECTIONS.auditoria, 'objetivo', uid),
    countWhere(db, COLLECTIONS.tokens, 'terminalId', uid),
  ]);

  const terminal = check.terminal;
  const blockers = [];
  if (!terminal && authUser) {
    blockers.push(
      'Existe una cuenta de Authentication pero no hay documento terminales/{uid}: ' +
        'no se puede verificar que sea una terminal.');
  }
  // Cualquier otro criterio incumplido implica que podría ser una cuenta normal.
  if (terminal || authUser) {
    for (const reason of check.reasons) {
      if (!reason.startsWith('criterio 1')) blockers.push(`No es una cuenta de terminal exclusiva (${reason}).`);
    }
  }

  const needsMark = Boolean(
    marcarRetirada && terminal && !(terminal.retirada && terminal.activo === false));
  const pending = Boolean(
    authUser || claveSnap.exists || pruebaSnap.exists || solicitudSnap.exists || needsMark);

  let state;
  if (blockers.length) state = State.blocked;
  else if (!pending) state = State.done;
  else if (authUser) state = State.full;
  else state = State.resume;

  return {
    uid,
    state,
    blockers,
    marcarRetirada,
    terminal,
    auth: authUser ? { email: authUser.email ?? null } : null,
    conservar: { asistencias, auditoria, qrTokens: tokens },
    eliminar: {
      cuentaAuth: Boolean(authUser),
      terminalClaves: claveSnap.exists,
      terminalPruebas: pruebaSnap.exists,
      solicitud: solicitudSnap.exists,
    },
    marcar: needsMark,
  };
}

function auditFields(report) {
  return [
    `nombre: ${report.terminal?.nombre ?? ''}`,
    ...(report.eliminar.cuentaAuth ? ['cuenta_authentication'] : []),
    ...(report.eliminar.terminalClaves ? ['terminalClaves'] : []),
    ...(report.eliminar.terminalPruebas ? ['terminalPruebas'] : []),
    ...(report.marcar ? ['terminales: retirada'] : ['terminales: conservada']),
  ];
}

/**
 * Ejecuta el retiro. `FieldValue` se inyecta como en `terminal_deletion.js`.
 * Lanza `TerminalDeletionError` con lo que se llegó a hacer si algo falla.
 */
async function executeRetirement({ auth, db, uid, FieldValue, marcarRetirada = false }) {
  const report = await inspectRetirement({ auth, db, uid, marcarRetirada });
  if (report.state === State.blocked) {
    throw new TerminalDeletionError(report.blockers.join(' '), emptyProgress());
  }
  const progress = emptyProgress();
  if (report.state === State.done) return { report, progress };

  if (report.auth) {
    try {
      await auth.deleteUser(uid);
      progress.cuentaAuth = true;
    } catch (e) {
      if (e && e.code === 'auth/user-not-found') progress.cuentaAuth = true;
      else {
        throw new TerminalDeletionError(
          `No se pudo eliminar la cuenta de Authentication: ${e.message}`, progress, e);
      }
    }
  } else {
    progress.cuentaAuth = true; // ya no existía (reanudación)
  }

  try {
    const batch = db.batch();
    batch.delete(db.collection(COLLECTIONS.claves).doc(uid));
    batch.delete(db.collection(COLLECTIONS.pruebas).doc(uid));
    batch.delete(db.collection(COLLECTIONS.solicitudes).doc(uid));
    if (report.marcar) {
      batch.update(db.collection(COLLECTIONS.terminales).doc(uid), {
        activo: false,
        retirada: true,
        retiradaEn: FieldValue.serverTimestamp(),
      });
    }
    batch.set(db.collection(COLLECTIONS.auditoria).doc(), {
      accion: AUDIT_ACTION,
      actorUid: AUDIT_ACTOR_UID,
      actorNombre: AUDIT_ACTOR_NAME,
      objetivo: uid,
      campos: auditFields(report),
      creadoEn: FieldValue.serverTimestamp(),
    });
    await batch.commit();
    progress.documentos = true;
  } catch (e) {
    throw new TerminalDeletionError(
      `No se pudieron actualizar los documentos de la terminal: ${e.message}`, progress, e);
  }
  return { report, progress };
}

module.exports = {
  AUDIT_ACTION,
  executeRetirement,
  inspectRetirement,
};
