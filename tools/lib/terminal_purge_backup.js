/**
 * Respaldo local y reverificación previos a una eventual purga. SOLO LECTURA
 * sobre Firebase: lee los documentos y cuentas que la simulación marcó como
 * candidatos y los devuelve como archivos en memoria; la CLI los guarda en
 * disco local (tools/backups/, fuera de git). No contiene ninguna operación
 * de escritura ni eliminación en Firebase.
 *
 * Del respaldo de Authentication se omiten el hash y la sal de contraseña.
 */
const crypto = require('node:crypto');

const ID_LINE = /^\s+(?:incluido|verificado)\s*:\s*(terminales|terminalPruebas|qrTokens|auditoria)\/([A-Za-z0-9]+)/;

/** Convierte Timestamps y otros tipos de Firestore a JSON legible. */
function plain(value) {
  if (value === null || typeof value !== 'object') return value;
  if (typeof value.toDate === 'function') return { _timestamp: value.toDate().toISOString() };
  if (Array.isArray(value)) return value.map(plain);
  if (typeof value.path === 'string' && typeof value.firestore === 'object') return { _ref: value.path };
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
}

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex');

/** Ids marcados como candidatos en un informe de simulación guardado. */
function candidatesFromReport(text) {
  const out = [];
  for (const line of text.split('\n')) {
    const m = ID_LINE.exec(line);
    if (m) out.push(`${m[1]}/${m[2]}`);
  }
  return new Set(out);
}

function candidatesFromPlan(plan) {
  const out = [];
  for (const id of plan.terminales.incluidos) out.push(`terminales/${id}`);
  for (const id of plan.terminalPruebas.incluidos) out.push(`terminalPruebas/${id}`);
  for (const t of plan.tokens.incluidos) out.push(`qrTokens/${t.id}`);
  for (const a of plan.auditoria.incluidos) out.push(`auditoria/${a.id}`);
  return new Set(out);
}

async function buildBackup({ auth, db, plan }) {
  const files = [];
  const addFile = (file, data) => {
    const content = `${JSON.stringify(data, null, 2)}\n`;
    files.push({ file, content, sha256: sha256(content) });
  };

  const accounts = [];
  for (const c of plan.cuentas.filter((x) => x.incluida)) {
    const u = await auth.getUser(c.uid);
    accounts.push({
      uid: u.uid, email: u.email ?? null, emailVerified: u.emailVerified, disabled: u.disabled,
      displayName: u.displayName ?? null, phoneNumber: u.phoneNumber ?? null,
      creationTime: u.metadata.creationTime, lastSignInTime: u.metadata.lastSignInTime ?? null,
      customClaims: u.customClaims ?? null,
      providers: u.providerData.map((p) => ({ providerId: p.providerId, uid: p.uid, email: p.email ?? null })),
    });
  }
  addFile('authentication/cuentas.json', accounts);

  const refs = [...candidatesFromPlan(plan)].sort();
  const missing = [];
  for (const ref of refs) {
    const snap = await db.doc(ref).get();
    if (!snap.exists) {
      missing.push(ref);
      continue;
    }
    addFile(`firestore/${ref}.json`, { _path: ref, data: plain(snap.data()) });
  }
  return { files, accounts: accounts.length, documents: refs.length - missing.length, missing };
}

module.exports = { buildBackup, candidatesFromPlan, candidatesFromReport, plain, sha256 };
