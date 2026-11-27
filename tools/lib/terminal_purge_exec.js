/**
 * Ejecución CONTROLADA de la purga del sistema antiguo de terminales. Solo
 * elimina los 38 elementos de la lista autorizada (`AUTHORIZED`), tras verificar
 * el respaldo y volver a consultar Firebase. Ante cualquier diferencia no elimina
 * nada. Si falla una eliminación, se detiene sin continuar y lo informa.
 *
 * Orden: qrTokens, auditoria, terminalPruebas, terminales y, por último, las
 * cuentas de Authentication. Cada documento se elimina con la precondición
 * `exists: true`. No toca terminalClaves ni solicitudesEliminacionTerminal.
 */
const fs = require('node:fs');
const path = require('node:path');
const { AUTHORIZED, collectPurgePlan } = require('./terminal_purge_plan');
const { candidatesFromPlan, sha256 } = require('./terminal_purge_backup');

const EXPECTED_TOTAL = 38;
const PROTECTED_COLLECTIONS = ['asistencias', 'usuarios', 'terminalClaves', 'solicitudesEliminacionTerminal'];

function authorizedRefs() {
  const refs = [];
  for (const id of AUTHORIZED.tokenIds) refs.push(`qrTokens/${id}`);
  for (const id of AUTHORIZED.auditIds) refs.push(`auditoria/${id}`);
  for (const uid of AUTHORIZED.accountUids) refs.push(`terminalPruebas/${uid}`);
  for (const uid of AUTHORIZED.accountUids) refs.push(`terminales/${uid}`);
  return refs;
}

/** Comprueba el manifiesto y el SHA-256 de cada archivo del respaldo. */
function verifyBackup(dir, refs) {
  const problems = [];
  const manifestPath = path.join(dir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) return ['no existe manifest.json en el respaldo'];
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const listed = new Set(manifest.archivos.map((a) => a.file));
  for (const a of manifest.archivos) {
    const file = path.join(dir, a.file);
    if (!fs.existsSync(file)) problems.push(`falta ${a.file}`);
    else if (sha256(fs.readFileSync(file, 'utf8')) !== a.sha256) problems.push(`hash distinto: ${a.file}`);
  }
  for (const ref of refs) if (!listed.has(`firestore/${ref}.json`)) problems.push(`el respaldo no incluye ${ref}`);
  if (!listed.has('authentication/cuentas.json')) problems.push('el respaldo no incluye las cuentas de Authentication');
  else {
    const accounts = JSON.parse(fs.readFileSync(path.join(dir, 'authentication/cuentas.json'), 'utf8'));
    const uids = accounts.map((a) => a.uid).sort().join(',');
    if (uids !== [...AUTHORIZED.accountUids].sort().join(',')) problems.push('las cuentas respaldadas no coinciden con la lista autorizada');
  }
  if (manifest.documentos !== refs.length || manifest.cuentasAuth !== AUTHORIZED.accountUids.length) {
    problems.push('el manifiesto no declara 35 documentos y 3 cuentas');
  }
  return problems;
}

async function countAll(db, auth) {
  const out = {};
  for (const c of [...PROTECTED_COLLECTIONS, 'qrTokens', 'auditoria', 'terminales', 'terminalPruebas']) {
    out[c] = (await db.collection(c).count().get()).data().count;
  }
  let n = 0;
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    n += page.users.length;
    token = page.pageToken;
  } while (token);
  out.authUsers = n;
  return out;
}

/**
 * @returns {Promise<{ok: boolean, abortado?: string[], eliminados: string[],
 *   pendientes: string[], error?: string, antes?: object, despues?: object}>}
 */
async function executePurge({ auth, db, backupDir }) {
  const refs = authorizedRefs();
  const problems = verifyBackup(backupDir, refs);
  if (problems.length) return { ok: false, abortado: [`respaldo inválido: ${problems.join('; ')}`], eliminados: [], pendientes: [] };

  const plan = await collectPurgePlan({ auth, db });
  const abort = [];
  if (plan.totales.general !== EXPECTED_TOTAL) abort.push(`el total en vivo es ${plan.totales.general}, no ${EXPECTED_TOTAL}`);
  abort.push(...plan.diferencias);
  const live = [...candidatesFromPlan(plan)].sort().join('|');
  if (live !== [...refs].sort().join('|')) abort.push('los candidatos en vivo no coinciden exactamente con la lista autorizada');
  const liveUids = plan.cuentas.filter((c) => c.incluida).map((c) => c.uid).sort().join(',');
  if (liveUids !== [...AUTHORIZED.accountUids].sort().join(',')) abort.push('las cuentas candidatas en vivo no coinciden con la lista autorizada');
  if (abort.length) return { ok: false, abortado: abort, eliminados: [], pendientes: [] };

  const antes = await countAll(db, auth);
  const eliminados = [];
  const pendientes = [...refs, ...AUTHORIZED.accountUids.map((u) => `auth/${u}`)];
  try {
    for (const ref of refs) {
      await db.doc(ref).delete({ exists: true });
      eliminados.push(ref);
      pendientes.shift();
    }
    for (const uid of AUTHORIZED.accountUids) {
      await auth.deleteUser(uid);
      eliminados.push(`auth/${uid}`);
      pendientes.shift();
    }
  } catch (e) {
    return { ok: false, eliminados, pendientes, error: e.message, antes };
  }
  const despues = await countAll(db, auth);
  return { ok: true, eliminados, pendientes, antes, despues };
}

/** Comprueba tras la purga que lo autorizado desapareció y lo protegido sigue. */
async function verifyAfter({ auth, db, antes, despues }) {
  const fallos = [];
  for (const ref of authorizedRefs()) {
    if ((await db.doc(ref).get()).exists) fallos.push(`sigue existiendo ${ref}`);
  }
  for (const uid of AUTHORIZED.accountUids) {
    try {
      await auth.getUser(uid);
      fallos.push(`sigue existiendo la cuenta ${uid}`);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
  }
  const esperado = {
    asistencias: antes.asistencias, usuarios: antes.usuarios,
    terminalClaves: antes.terminalClaves, solicitudesEliminacionTerminal: antes.solicitudesEliminacionTerminal,
    qrTokens: antes.qrTokens - 8, auditoria: antes.auditoria - 21,
    terminales: antes.terminales - 3, terminalPruebas: antes.terminalPruebas - 3,
    authUsers: antes.authUsers - 3,
  };
  for (const [k, v] of Object.entries(esperado)) {
    if (despues[k] !== v) fallos.push(`${k}: esperado ${v}, hay ${despues[k]}`);
  }
  return { fallos, esperado };
}

module.exports = { EXPECTED_TOTAL, authorizedRefs, verifyBackup, executePurge, verifyAfter };
