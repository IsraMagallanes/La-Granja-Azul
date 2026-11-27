/**
 * Inventario de cuentas de terminal antiguas. SOLO LECTURA: no modifica
 * Authentication ni Firestore (solo `listUsers`, `get` y consultas `count`/`where`).
 *
 * Por cada candidato (documento en `terminales` o cuenta de Authentication sin
 * perfil) aplica los cuatro criterios de `terminal_criteria.js` y emite un
 * veredicto. Además resume los `qrTokens` (cantidades, estado y referencias) para
 * decidir después, sin purgar nada.
 */
const { checkExclusivity, countWhere } = require('./terminal_criteria');

const TOKEN_LIFETIME_MS = 45 * 1000;
const IN_CHUNK = 10;
const MAX_UNUSED_REFERENCE_CHECK = 5000;

const Verdict = Object.freeze({
  exclusive: 'TERMINAL EXCLUSIVA',
  excluded: 'EXCLUIDA',
  documentsOnly: 'SIN CUENTA AUTH (solo documentos)',
});

const mask = (email = '') => email.replace(/^(.{2}).*(@.*)$/, '$1•••$2');

async function listAllAuthUsers(auth) {
  const users = [];
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    users.push(...page.users);
    token = page.pageToken;
  } while (token);
  return users;
}

async function inspectCandidate({ db, uid, authUser, claveIds, pruebaIds, solicitudIds }) {
  const check = await checkExclusivity({ db, uid, email: authUser?.email });
  const [asistencias, auditoriaObjetivo, tokensUsados] = await Promise.all([
    countWhere(db, 'asistencias', 'terminalId', uid),
    countWhere(db, 'auditoria', 'objetivo', uid),
    countWhere(db, 'qrTokens', 'terminalId', uid),
  ]);

  let verdict;
  if (!authUser && check.terminal && !check.profileRole) verdict = Verdict.documentsOnly;
  else if (authUser && check.exclusive) verdict = Verdict.exclusive;
  else verdict = Verdict.excluded;

  return {
    uid,
    verdict,
    reasons: verdict === Verdict.excluded
      ? (check.reasons.length ? check.reasons : ['sin cuenta ni documentos verificables'])
      : [],
    nombre: check.terminal?.nombre ?? null,
    activo: check.terminal ? check.terminal.activo !== false : null,
    retirada: check.terminal?.retirada ?? false,
    perfilRol: check.profileRole,
    auth: authUser
      ? {
          email: mask(authUser.email ?? ''),
          emailVerified: authUser.emailVerified,
          disabled: authUser.disabled,
          ultimoAcceso: authUser.metadata?.lastSignInTime ?? null,
          creada: authUser.metadata?.creationTime ?? null,
        }
      : null,
    documentos: {
      terminales: Boolean(check.terminal),
      terminalClaves: claveIds.has(uid),
      terminalPruebas: pruebaIds.has(uid),
      solicitudEliminacion: solicitudIds.has(uid),
    },
    referencias: {
      asistenciasComoTerminal: asistencias,
      auditoriaComoObjetivo: auditoriaObjetivo,
      qrTokensUsados: tokensUsados,
    },
  };
}

/** Cantidades, estado y referencias de los `qrTokens`. No borra nada. */
async function inspectTokens({ db, now }) {
  const [total, unusedSnap, qrAsistencias] = await Promise.all([
    db.collection('qrTokens').count().get().then((s) => s.data().count),
    db.collection('qrTokens').where('usadoEn', '==', null)
      .select('creadoEn', 'tipo', 'terminalId').get(),
    countWhere(db, 'asistencias', 'origen', 'qr'),
  ]);

  const unused = unusedSnap.docs.map((d) => ({
    id: d.id,
    creadoEn: d.get('creadoEn')?.toDate?.() ?? null,
    tipo: d.get('tipo') ?? null,
    terminalId: d.get('terminalId') ?? null,
  }));
  const expired = unused.filter(
    (t) => !t.creadoEn || now.getTime() - t.creadoEn.getTime() > TOKEN_LIFETIME_MS);
  const dates = unused.map((t) => t.creadoEn).filter(Boolean).sort((a, b) => a - b);

  // ¿Alguna asistencia apunta a un token sin usar? No debería ocurrir.
  const toCheck = unused.slice(0, MAX_UNUSED_REFERENCE_CHECK).map((t) => t.id);
  let referenced = 0;
  for (let i = 0; i < toCheck.length; i += IN_CHUNK) {
    const ids = toCheck.slice(i, i + IN_CHUNK);
    const [entrada, salida] = await Promise.all([
      db.collection('asistencias').where('tokenId', 'in', ids).count().get(),
      db.collection('asistencias').where('salidaTokenId', 'in', ids).count().get(),
    ]);
    referenced += entrada.data().count + salida.data().count;
  }

  return {
    total,
    usados: total - unused.length,
    sinUsar: unused.length,
    sinUsarVencidos: expired.length,
    sinUsarVigentes: unused.length - expired.length,
    sinUsarPorTipo: {
      entrada: unused.filter((t) => t.tipo === 'entrada').length,
      salida: unused.filter((t) => t.tipo === 'salida').length,
    },
    sinUsarConTerminalAsignada: unused.filter((t) => t.terminalId).length,
    sinUsarMasAntiguo: dates[0]?.toISOString() ?? null,
    sinUsarMasReciente: dates[dates.length - 1]?.toISOString() ?? null,
    asistenciasQr: qrAsistencias,
    asistenciasQueReferencianTokensSinUsar: referenced,
    referenciasRevisadas: toCheck.length,
    referenciasSinRevisar: Math.max(0, unused.length - toCheck.length),
  };
}

async function collectInventory({ auth, db, now = new Date() }) {
  const [authUsers, terminals, profileSnap, claves, pruebas, solicitudes] = await Promise.all([
    listAllAuthUsers(auth),
    db.collection('terminales').select('nombre').get(),
    db.collection('usuarios').select().get(),
    db.collection('terminalClaves').select().get(),
    db.collection('terminalPruebas').select().get(),
    db.collection('solicitudesEliminacionTerminal').select().get(),
  ]);
  const profileIds = new Set(profileSnap.docs.map((d) => d.id));
  const terminalIds = new Set(terminals.docs.map((d) => d.id));
  const byUid = new Map(authUsers.map((u) => [u.uid, u]));
  const ids = (snap) => new Set(snap.docs.map((d) => d.id));
  const claveIds = ids(claves);
  const pruebaIds = ids(pruebas);
  const solicitudIds = ids(solicitudes);

  const candidates = new Set(terminalIds);
  for (const u of authUsers) {
    if (!profileIds.has(u.uid)) candidates.add(u.uid); // sin perfil: cuenta huérfana o terminal
  }
  const ordinary = authUsers.filter(
    (u) => profileIds.has(u.uid) && !terminalIds.has(u.uid)).length;

  const accounts = [];
  for (const uid of candidates) {
    accounts.push(await inspectCandidate({
      db, uid, authUser: byUid.get(uid) ?? null, claveIds, pruebaIds, solicitudIds,
    }));
  }
  const order = { [Verdict.exclusive]: 0, [Verdict.excluded]: 1, [Verdict.documentsOnly]: 2 };
  accounts.sort((a, b) => order[a.verdict] - order[b.verdict]
    || String(a.nombre).localeCompare(String(b.nombre)));

  const count = (v) => accounts.filter((a) => a.verdict === v).length;
  return {
    generado: now.toISOString(),
    resumen: {
      cuentasAuthTotal: authUsers.length,
      cuentasNormalesIgnoradas: ordinary,
      documentosTerminales: terminalIds.size,
      candidatas: accounts.length,
      terminalesExclusivas: count(Verdict.exclusive),
      excluidas: count(Verdict.excluded),
      sinCuentaAuth: count(Verdict.documentsOnly),
    },
    cuentas: accounts,
    tokens: await inspectTokens({ db, now }),
  };
}

const yesNo = (v) => (v ? 'sí' : 'no');

function formatReport(inv, project) {
  const out = [];
  const r = inv.resumen;
  out.push(`Proyecto : ${project}`);
  out.push('Modo     : SOLO LECTURA (no se modifica Authentication ni Firestore)');
  out.push(`Generado : ${inv.generado}`);
  out.push('');
  out.push(`Cuentas en Authentication      : ${r.cuentasAuthTotal}`);
  out.push(`  normales (con perfil), ignoradas : ${r.cuentasNormalesIgnoradas}`);
  out.push(`Documentos en terminales       : ${r.documentosTerminales}`);
  out.push(`Candidatas analizadas          : ${r.candidatas}`);
  out.push(`  ${Verdict.exclusive}  : ${r.terminalesExclusivas}`);
  out.push(`  ${Verdict.excluded}            : ${r.excluidas}`);
  out.push(`  ${Verdict.documentsOnly} : ${r.sinCuentaAuth}`);
  for (const a of inv.cuentas) {
    out.push('');
    out.push(`── ${a.verdict} ─────────────────────────────`);
    out.push(`UID        : ${a.uid}`);
    out.push(`Terminal   : ${a.nombre === null ? '(sin documento terminales/{uid})' : `"${a.nombre}" — ${a.activo ? 'activa' : 'inhabilitada'}${a.retirada ? ', retirada' : ''}`}`);
    out.push(a.auth
      ? `Auth       : ${a.auth.email} | verificado=${yesNo(a.auth.emailVerified)} | deshabilitada=${yesNo(a.auth.disabled)} | último acceso=${a.auth.ultimoAcceso ?? 'nunca'}`
      : 'Auth       : no existe cuenta de Authentication');
    out.push(`Documentos : terminales=${yesNo(a.documentos.terminales)} terminalClaves=${yesNo(a.documentos.terminalClaves)} terminalPruebas=${yesNo(a.documentos.terminalPruebas)} solicitud=${yesNo(a.documentos.solicitudEliminacion)}`);
    out.push(`Referencias: asistencias=${a.referencias.asistenciasComoTerminal} auditoría(objetivo)=${a.referencias.auditoriaComoObjetivo} qrTokens usados=${a.referencias.qrTokensUsados}`);
    if (a.reasons.length) a.reasons.forEach((x) => out.push(`  ✗ ${x}`));
    if (a.verdict === Verdict.exclusive) out.push('  ✓ cumple los 4 criterios (no hay nada de personal asociado)');
  }
  const t = inv.tokens;
  out.push('');
  out.push('── qrTokens (solo informe; no se purga nada) ─────────────');
  out.push(`Total: ${t.total} | usados: ${t.usados} | sin usar: ${t.sinUsar}`);
  out.push(`Sin usar: vencidos (>45 s)=${t.sinUsarVencidos} vigentes=${t.sinUsarVigentes} | entrada=${t.sinUsarPorTipo.entrada} salida=${t.sinUsarPorTipo.salida}`);
  out.push(`Sin usar con terminal asignada (anomalía si > 0): ${t.sinUsarConTerminalAsignada}`);
  out.push(`Sin usar: más antiguo=${t.sinUsarMasAntiguo ?? '-'} más reciente=${t.sinUsarMasReciente ?? '-'}`);
  out.push(`Asistencias con origen QR: ${t.asistenciasQr}`);
  out.push(`Asistencias que referencian tokens sin usar: ${t.asistenciasQueReferencianTokensSinUsar} (revisados ${t.referenciasRevisadas}, sin revisar ${t.referenciasSinRevisar})`);
  out.push('Los tokens usados se conservan siempre: son la referencia histórica de las asistencias.');
  return out.join('\n');
}

module.exports = { Verdict, collectInventory, formatReport };
