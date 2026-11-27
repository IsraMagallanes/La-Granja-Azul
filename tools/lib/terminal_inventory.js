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
const MAX_LISTED = 200;

/** Acciones de auditoría del sistema antiguo de terminales. */
const TERMINAL_AUDIT_ACTIONS = [
  'autorizar_terminal', 'revocar_terminal', 'restablecer_terminal',
  'solicitar_eliminacion_terminal', 'eliminar_terminal', 'retirar_cuenta_terminal',
];

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

/**
 * Separa los `qrTokens` del sistema nuevo (`generadorUid`) de los del antiguo
 * (`uid` del trabajador + `tipo` + `terminalId`) y señala cuáles de estos
 * últimos son prescindibles. SOLO LECTURA.
 *
 *  - nuevos: del flujo actual «Generar QR»; nunca se tocan.
 *  - legado usado y referenciado por una asistencia: historia de trabajadores
 *    reales; se conserva.
 *  - legado sin usar o usado sin ninguna asistencia que lo referencie: residuos
 *    del flujo antiguo, sin utilidad.
 */
async function classifyTokens({ db, now }) {
  const [tokens, attendance] = await Promise.all([
    db.collection('qrTokens').select('generadorUid', 'usadoEn', 'terminalId', 'creadoEn', 'tipo').get(),
    db.collection('asistencias').select('tokenId', 'salidaTokenId').get(),
  ]);
  const referenced = new Set();
  for (const d of attendance.docs) {
    for (const k of ['tokenId', 'salidaTokenId']) {
      const v = d.get(k);
      if (typeof v === 'string') referenced.add(v);
    }
  }
  const out = { nuevos: 0, legadoUsadoReferenciado: 0, legadoUsadoSinReferencia: [], legadoSinUsar: [] };
  for (const d of tokens.docs) {
    const created = d.get('creadoEn')?.toDate?.() ?? null;
    const row = {
      id: d.id,
      tipo: d.get('tipo') ?? null,
      terminalId: d.get('terminalId') ?? null,
      creadoEn: created ? created.toISOString() : null,
      edadHoras: created ? Math.round((now.getTime() - created.getTime()) / 3600000) : null,
    };
    if (d.get('generadorUid')) out.nuevos += 1;
    else if (d.get('usadoEn')) {
      if (referenced.has(d.id)) out.legadoUsadoReferenciado += 1;
      else out.legadoUsadoSinReferencia.push(row);
    } else out.legadoSinUsar.push(row);
  }
  return out;
}

/** Registros de auditoría del sistema antiguo de terminales (no se borran por defecto). */
async function inspectTerminalAudit({ db, terminalUids }) {
  const snap = await db.collection('auditoria').where('accion', 'in', TERMINAL_AUDIT_ACTIONS)
    .select('accion', 'objetivo', 'actorUid', 'creadoEn').get();
  const rows = snap.docs.map((d) => ({
    id: d.id,
    accion: d.get('accion'),
    objetivo: d.get('objetivo') ?? null,
    actorUid: d.get('actorUid') ?? null,
    creadoEn: d.get('creadoEn')?.toDate?.()?.toISOString() ?? null,
    objetivoEsTerminal: terminalUids.has(d.get('objetivo')),
  }));
  return rows;
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
    clasificacionTokens: await classifyTokens({ db, now }),
    auditoriaTerminales: await inspectTerminalAudit({ db, terminalUids: terminalIds }),
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
  out.push('Los tokens usados y referenciados se conservan siempre: son la referencia histórica de las asistencias.');

  const c = inv.clasificacionTokens;
  out.push('');
  out.push('── Clasificación de qrTokens (sistema nuevo vs. antiguo) ─────────────');
  out.push(`Del sistema NUEVO (generadorUid), no se tocan : ` + c.nuevos);
  out.push(`Antiguos usados y referenciados por una asistencia (se conservan): ` + c.legadoUsadoReferenciado);
  out.push(`Antiguos usados SIN asistencia que los referencie: ` + c.legadoUsadoSinReferencia.length);
  out.push(`Antiguos SIN usar (residuos): ` + c.legadoSinUsar.length);
  for (const [titulo, rows] of [['usados sin referencia', c.legadoUsadoSinReferencia], ['sin usar', c.legadoSinUsar]]) {
    for (const t of rows.slice(0, MAX_LISTED)) {
      out.push(`  - qrTokens/` + t.id + ` (` + titulo + `, tipo=` + (t.tipo ?? '-') + `, terminal=` + (t.terminalId ?? '-') + `, creado=` + (t.creadoEn ?? '-') + `)`);
    }
    if (rows.length > MAX_LISTED) out.push(`  … y ` + (rows.length - MAX_LISTED) + ` más (` + titulo + `)`);
  }

  out.push('');
  out.push('── Auditoría del sistema antiguo de terminales (no se toca por defecto) ─────────────');
  out.push('Registros: ' + inv.auditoriaTerminales.length);
  for (const a of inv.auditoriaTerminales.slice(0, MAX_LISTED)) {
    out.push(`  - auditoria/` + a.id + ` accion=` + a.accion + ` objetivo=` + (a.objetivo ?? '-') + ` actor=` + (a.actorUid ?? '-') + ` ` + (a.creadoEn ?? ''));
  }
  return out.join('\n');
}

module.exports = { Verdict, collectInventory, formatReport };
