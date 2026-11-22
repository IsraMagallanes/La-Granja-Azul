/**
 * Eliminación definitiva de una terminal de asistencia (lógica sin E/S de
 * consola, para poder probarla con los emuladores).
 *
 * Elimina: cuenta de Authentication, `terminales/{uid}`, `terminalClaves/{uid}`,
 * `terminalPruebas/{uid}`, la solicitud hecha desde la app
 * (`solicitudesEliminacionTerminal/{uid}`) y los `qrTokens` con
 * `terminalId == uid`.
 * Conserva SIEMPRE: `asistencias` y `auditoria` (solo se añade una entrada).
 *
 * Orden y reanudación: primero la cuenta de Authentication, después los tokens
 * y, al final y en un único lote atómico, los tres documentos operativos junto
 * con la entrada de auditoría. `terminales/{uid}` es el último en desaparecer,
 * de modo que mientras exista la operación está pendiente (y la app sigue
 * mostrando la terminal inhabilitada, que es la verdad). Si falla algo, repetir
 * el comando completa lo que falte.
 */
const COLLECTIONS = {
  terminales: 'terminales',
  claves: 'terminalClaves',
  pruebas: 'terminalPruebas',
  tokens: 'qrTokens',
  solicitudes: 'solicitudesEliminacionTerminal',
  asistencias: 'asistencias',
  auditoria: 'auditoria',
  usuarios: 'usuarios',
};

/** Identificadores del script en la auditoría (no hay sesión de usuario). */
const AUDIT_ACTOR_UID = 'script-local';
const AUDIT_ACTOR_NAME = 'Script administrativo local';
const AUDIT_ACTION = 'eliminar_terminal';

// Firestore admite 500 operaciones por lote.
const CHUNK = 400;

const UID_RE = /^[A-Za-z0-9]{6,128}$/;

/** Estados posibles tras inspeccionar. */
const State = Object.freeze({
  /** Cuenta y documento existen: eliminación completa. */
  full: 'completa',
  /** Authentication ya se eliminó pero quedan documentos: se reanuda. */
  resume: 'reanudar',
  /** No queda nada de la terminal: nada que hacer. */
  done: 'ya-eliminada',
  /** Hay motivos para no continuar (ver `blockers`). */
  blocked: 'bloqueada',
});

class TerminalDeletionError extends Error {
  /** @param progress lo que SÍ se llegó a eliminar antes del fallo. */
  constructor(message, progress, cause) {
    super(message);
    this.name = 'TerminalDeletionError';
    this.progress = progress;
    this.cause = cause;
  }
}

function assertValidUid(uid) {
  if (typeof uid !== 'string' || !UID_RE.test(uid)) {
    throw new Error('UID no válido: debe tener entre 6 y 128 letras o dígitos.');
  }
}

async function countWhere(db, collection, field, value) {
  const snap = await db.collection(collection).where(field, '==', value).count().get();
  return snap.data().count;
}

async function findAuthUser(auth, uid) {
  try {
    return await auth.getUser(uid);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

/**
 * Lee el estado actual sin modificar nada. Es lo que muestra el modo
 * simulación y lo que `execute` vuelve a comprobar antes de borrar.
 */
async function inspect({ auth, db, uid, requireRequest = false }) {
  assertValidUid(uid);
  const [terminalSnap, staffSnap, authUser, requestSnap] = await Promise.all([
    db.collection(COLLECTIONS.terminales).doc(uid).get(),
    db.collection(COLLECTIONS.usuarios).doc(uid).get(),
    findAuthUser(auth, uid),
    db.collection(COLLECTIONS.solicitudes).doc(uid).get(),
  ]);
  const [asistencias, auditoria, qrTokens, clave, prueba] = await Promise.all([
    countWhere(db, COLLECTIONS.asistencias, 'terminalId', uid),
    countWhere(db, COLLECTIONS.auditoria, 'objetivo', uid),
    countWhere(db, COLLECTIONS.tokens, 'terminalId', uid),
    db.collection(COLLECTIONS.claves).doc(uid).get(),
    db.collection(COLLECTIONS.pruebas).doc(uid).get(),
  ]);

  const terminal = terminalSnap.exists
    ? { nombre: terminalSnap.get('nombre') ?? '', activo: terminalSnap.get('activo') }
    : null;
  const blockers = [];

  if (staffSnap.exists) {
    blockers.push(
      'El UID pertenece a una cuenta de personal (usuarios/{uid}). Nunca se elimina desde este script.');
  }
  if (terminal && terminal.activo !== false) {
    blockers.push('La terminal no está inhabilitada. Inhabilítala primero desde la app.');
  }
  // Decisión técnica 1: la eliminación se solicita desde la app (Superadmin,
  // auditada) y este script la procesa. Sin solicitud no se elimina.
  if (requireRequest && terminal && !requestSnap.exists) {
    blockers.push(
      'No hay una solicitud de eliminación hecha desde la app (Terminales → ' +
        'Solicitar eliminación definitiva).');
  }
  if (!terminal && authUser) {
    blockers.push(
      'Existe una cuenta de Authentication pero no hay documento terminales/{uid}: ' +
        'no se puede verificar que sea una terminal inhabilitada.');
  }

  let state;
  if (blockers.length) state = State.blocked;
  else if (terminal && authUser) state = State.full;
  else if (terminal && !authUser) state = State.resume;
  else state = State.done;

  return {
    uid,
    state,
    blockers,
    terminal,
    solicitud: requestSnap.exists
      ? { solicitadoPor: requestSnap.get('solicitadoPor') ?? null }
      : null,
    auth: authUser ? { email: authUser.email ?? null } : null,
    conservar: { asistencias, auditoria },
    eliminar: {
      cuentaAuth: Boolean(authUser),
      terminales: terminalSnap.exists,
      terminalClaves: clave.exists,
      terminalPruebas: prueba.exists,
      solicitud: requestSnap.exists,
      qrTokens,
    },
  };
}

async function deleteTokens(db, uid) {
  let deleted = 0;
  for (;;) {
    const page = await db
      .collection(COLLECTIONS.tokens)
      .where('terminalId', '==', uid)
      .limit(CHUNK)
      .get();
    if (page.empty) return deleted;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += page.size;
  }
}

/**
 * Ejecuta la eliminación. `FieldValue` se inyecta para no depender del módulo
 * `firebase-admin` aquí (el CLI y las pruebas pasan `admin.firestore.FieldValue`).
 * Lanza `TerminalDeletionError` con lo que se llegó a eliminar si algo falla.
 */
async function execute({ auth, db, uid, FieldValue, requireRequest = false }) {
  const report = await inspect({ auth, db, uid, requireRequest });
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
      // Se eliminó entre la inspección y ahora: el objetivo ya está cumplido.
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
    progress.qrTokens = await deleteTokens(db, uid);
  } catch (e) {
    throw new TerminalDeletionError(
      `No se pudieron eliminar los tokens QR: ${e.message}`, progress, e);
  }

  try {
    const batch = db.batch();
    batch.delete(db.collection(COLLECTIONS.claves).doc(uid));
    batch.delete(db.collection(COLLECTIONS.pruebas).doc(uid));
    batch.delete(db.collection(COLLECTIONS.solicitudes).doc(uid));
    batch.set(db.collection(COLLECTIONS.auditoria).doc(), {
      accion: AUDIT_ACTION,
      actorUid: AUDIT_ACTOR_UID,
      actorNombre: AUDIT_ACTOR_NAME,
      objetivo: uid,
      campos: auditFields(report),
      creadoEn: FieldValue.serverTimestamp(),
    });
    // El documento de la terminal es lo último que desaparece.
    batch.delete(db.collection(COLLECTIONS.terminales).doc(uid));
    await batch.commit();
    progress.documentos = true;
  } catch (e) {
    throw new TerminalDeletionError(
      `No se pudieron eliminar los documentos de la terminal: ${e.message}`, progress, e);
  }
  return { report, progress };
}

/**
 * Mismo esquema que el resto de la auditoría (`campos` es una lista de textos).
 * Se deja el nombre: es lo único que identifica el UID tras borrar la terminal.
 */
function auditFields(report) {
  return [
    `nombre: ${report.terminal?.nombre ?? ''}`,
    'cuenta_authentication',
    'terminales',
    'terminalClaves',
    'terminalPruebas',
    'qrTokens',
  ];
}

/** Solicitudes de eliminación pendientes, hechas desde la app. Solo lectura. */
async function listPending({ db }) {
  const snap = await db.collection(COLLECTIONS.solicitudes).get();
  return snap.docs
    .map((d) => ({
      uid: d.id,
      nombre: d.get('nombre') ?? '',
      solicitadoPor: d.get('solicitadoPor') ?? null,
      solicitadoEn: d.get('solicitadoEn')?.toDate?.() ?? null,
    }))
    .sort((a, b) => String(a.solicitadoEn).localeCompare(String(b.solicitadoEn)));
}

function emptyProgress() {
  return { cuentaAuth: false, qrTokens: 0, documentos: false };
}

module.exports = {
  COLLECTIONS,
  AUDIT_ACTION,
  AUDIT_ACTOR_NAME,
  AUDIT_ACTOR_UID,
  State,
  TerminalDeletionError,
  assertValidUid,
  execute,
  inspect,
  listPending,
};
