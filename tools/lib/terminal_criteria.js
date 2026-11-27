/**
 * Criterios para decidir si un UID es una cuenta creada EXCLUSIVAMENTE para una
 * antigua terminal de asistencia. Solo lectura: no modifica nada.
 *
 * Una cuenta es «terminal exclusiva» únicamente si cumple las cuatro condiciones:
 *   1. existe `terminales/{uid}`;
 *   2. NO existe `usuarios/{uid}` (no es personal: ni trabajador, ni Caja, ni
 *      Admin, ni Superadmin);
 *   3. ni su correo (`correos/{correo}`) ni su UID figuran en los índices de
 *      personal (`correos`, `documentos`);
 *   4. su UID nunca aparece como trabajador (`asistencias.uid`) ni como actor
 *      (`auditoria.actorUid`); solo puede aparecer como `terminalId`.
 *
 * Es la única definición de «cuenta de terminal»: la usan el inventario y el
 * modo de retiro, de modo que ninguno puede tocar una cuenta que el otro
 * excluiría.
 */
const COLLECTIONS = {
  terminales: 'terminales',
  usuarios: 'usuarios',
  correos: 'correos',
  documentos: 'documentos',
  asistencias: 'asistencias',
  auditoria: 'auditoria',
};

async function countWhere(db, collection, field, value) {
  const snap = await db.collection(collection).where(field, '==', value).count().get();
  return snap.data().count;
}

/**
 * @param email correo de la cuenta de Authentication (puede faltar si no hay cuenta).
 * @returns {Promise<{exclusive: boolean, reasons: string[], terminal: object|null,
 *   profileRole: string|null}>} `reasons` vacío ⇔ cumple los cuatro criterios.
 */
async function checkExclusivity({ db, uid, email }) {
  const mail = String(email ?? '').toLowerCase();
  const [terminalSnap, profileSnap, mailDoc, mailByUid, docByUid, asWorker, asActor] =
    await Promise.all([
      db.collection(COLLECTIONS.terminales).doc(uid).get(),
      db.collection(COLLECTIONS.usuarios).doc(uid).get(),
      // Un correo vacío no es un id de documento válido.
      mail ? db.collection(COLLECTIONS.correos).doc(mail).get() : Promise.resolve(null),
      countWhere(db, COLLECTIONS.correos, 'uid', uid),
      countWhere(db, COLLECTIONS.documentos, 'uid', uid),
      countWhere(db, COLLECTIONS.asistencias, 'uid', uid),
      countWhere(db, COLLECTIONS.auditoria, 'actorUid', uid),
    ]);

  const reasons = [];
  if (!terminalSnap.exists) reasons.push('criterio 1: no existe terminales/{uid}');
  if (profileSnap.exists) {
    reasons.push(`criterio 2: tiene perfil en usuarios (rol ${profileSnap.get('rol') ?? '?'})`);
  }
  if ((mailDoc && mailDoc.exists) || mailByUid > 0) {
    reasons.push('criterio 3: su correo o UID figura en el índice correos');
  }
  if (docByUid > 0) reasons.push('criterio 3: su UID figura en el índice documentos');
  if (asWorker > 0) {
    reasons.push(`criterio 4: aparece como trabajador en ${asWorker} asistencia(s)`);
  }
  if (asActor > 0) {
    reasons.push(`criterio 4: aparece como actor en ${asActor} registro(s) de auditoría`);
  }
  return {
    exclusive: reasons.length === 0,
    reasons,
    terminal: terminalSnap.exists
      ? {
          nombre: terminalSnap.get('nombre') ?? '',
          activo: terminalSnap.get('activo'),
          retirada: terminalSnap.get('retirada') === true,
        }
      : null,
    profileRole: profileSnap.exists ? (profileSnap.get('rol') ?? '?') : null,
  };
}

module.exports = { COLLECTIONS, checkExclusivity, countWhere };
