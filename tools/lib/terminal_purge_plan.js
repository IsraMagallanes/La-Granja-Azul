/**
 * Simulación de la purga del sistema antiguo de terminales. SOLO LECTURA: este
 * módulo únicamente llama a `getUser`, `get` y consultas `count`/`where`; no
 * existe ninguna ruta de código que escriba o elimine (hay una prueba que lo
 * comprueba sobre el texto de los archivos).
 *
 * Solo considera los elementos autorizados de forma explícita (UIDs, IDs de
 * tokens y de auditoría). Todo lo que no coincida con la clasificación esperada
 * se excluye y se explica el motivo.
 */
const { checkExclusivity, countWhere } = require('./terminal_criteria');

/** Acciones de auditoría del sistema antiguo de terminales. */
const TERMINAL_AUDIT_ACTIONS = [
  'autorizar_terminal', 'revocar_terminal', 'restablecer_terminal',
  'solicitar_eliminacion_terminal', 'eliminar_terminal', 'retirar_cuenta_terminal',
];

const AUTHORIZED = Object.freeze({
  accountUids: [
    'qcws9YWDVPef3THHTQESmdE3LyC3',
    'WlEJWNwIvFRzULaO1hQ6vYxbTjF2',
    '29519GHJw0RHouh6yj4lcdQkIVg1',
  ],
  tokenIds: [
    '110560ac6310327dbdac2f988d9dd927',
    '4b3d58a3beead6390b51b387e873ec7a',
    '51aa2f1207f6cb3791fec24739c8dab8',
    'c47af7a5456b143bc508765b495b29d3',
    'd52de7cb2c88db3ad85834ca404de66f',
    'd914e5823d660feee9894dadecfc70d2',
    'f3a1bdcbf26a64f50342fb7d435d3e7f',
    'fc1b73fbd550dba8dac2cc1b9e0def02',
  ],
  auditIds: [
    '1ejKuRthkshgQ1kZJm7g', '2mdEUQV0MDSdo5YbJLdc', '38I6AXVHy85gsU3kbXS3',
    '4IQETUcGGBoGOQ2K4mdZ', 'BkxY2PmQPuIUYOZ66l5U', 'Eol7tjmCuZFpXKaynoWr',
    'GBXBuG8OpNdd7pe7P1Od', 'GQQi0n2dDRBi9WGSZDWI', 'Q4kBgPlaOuXgjjvzKQmJ',
    'SFoTanu26fvtOFnhMzQF', 'UNzuiU8Tmggugp5KeI3K', 'W5GRB2KGvpCTnSsuiu39',
    'YDa9i8FqxZegqXm79K1x', 'aEg3jTnOyjpqh44HxIUk', 'cB71QH9sHA5TqiKH0K3p',
    'gQY7it9habhwF5pJqwJj', 'gmf76Ifgkjl2KJu9kSoB', 'hGZ8SV6z4Ptx1juu7jTo',
    'hI6NCl1aEbOTQVTliP7U', 'le4CYeEmverjeOyi8hYG', 'vxdXLu0AsZtDG3Airqgk',
  ],
  expected: { terminales: 3, terminalPruebas: 3 },
});

const IN_CHUNK = 10;
const mask = (email = '') => email.replace(/^(.{2}).*(@.*)$/, '$1•••$2');
const iso = (ts) => ts?.toDate?.()?.toISOString() ?? null;
const isNotFound = (e) => e?.code === 'auth/user-not-found';

async function inspectAccount({ auth, db, uid }) {
  let authUser = null;
  try {
    authUser = await auth.getUser(uid);
  } catch (e) {
    if (!isNotFound(e)) throw e;
  }
  const [check, clave, prueba, solicitud, mailsByUid, docsByUid, asTerminal, asTarget, tokens] =
    await Promise.all([
      checkExclusivity({ db, uid, email: authUser?.email }),
      db.collection('terminalClaves').doc(uid).get(),
      db.collection('terminalPruebas').doc(uid).get(),
      db.collection('solicitudesEliminacionTerminal').doc(uid).get(),
      countWhere(db, 'correos', 'uid', uid),
      countWhere(db, 'documentos', 'uid', uid),
      countWhere(db, 'asistencias', 'terminalId', uid),
      countWhere(db, 'auditoria', 'objetivo', uid),
      countWhere(db, 'qrTokens', 'terminalId', uid),
    ]);

  const reasons = [];
  if (!authUser) reasons.push('no existe la cuenta en Authentication');
  reasons.push(...check.reasons);
  return {
    uid,
    incluida: reasons.length === 0,
    motivos: reasons,
    nombre: check.terminal?.nombre ?? null,
    perfilRol: check.profileRole,
    auth: authUser
      ? {
          email: mask(authUser.email ?? ''),
          deshabilitada: authUser.disabled,
          ultimoAcceso: authUser.metadata?.lastSignInTime ?? null,
          creada: authUser.metadata?.creationTime ?? null,
        }
      : null,
    documentosAsociados: {
      'terminales': check.terminal !== null,
      'terminalClaves': clave.exists,
      'terminalPruebas': prueba.exists,
      'solicitudesEliminacionTerminal': solicitud.exists,
      'usuarios (debe ser no)': check.profileRole !== null,
      'correos/documentos por uid (debe ser 0)': mailsByUid + docsByUid,
    },
    referenciasQueSeConservan: {
      asistenciasComoTerminal: asTerminal,
      auditoriaComoObjetivo: asTarget,
      qrTokensConTerminalId: tokens,
    },
  };
}

/** Lista una colección completa (solo ids) y separa los ids autorizados. */
async function inspectCollection({ db, name, includedUids, expected }) {
  const snap = await db.collection(name).select().get();
  const ids = snap.docs.map((d) => d.id);
  const incluidos = ids.filter((id) => includedUids.has(id));
  const excluidos = ids
    .filter((id) => !includedUids.has(id))
    .map((id) => ({ id, motivo: 'su id no corresponde a una cuenta autorizada e incluida' }));
  const faltantes = [...includedUids].filter((uid) => !ids.includes(uid));
  return { coleccion: name, total: ids.length, esperados: expected, incluidos, excluidos, faltantes };
}

async function referencedTokenIds({ db, ids }) {
  const found = [];
  for (let i = 0; i < ids.length; i += IN_CHUNK) {
    const chunk = ids.slice(i, i + IN_CHUNK);
    for (const field of ['tokenId', 'salidaTokenId']) {
      const snap = await db.collection('asistencias').where(field, 'in', chunk).select(field).get();
      for (const d of snap.docs) found.push(d.get(field));
    }
  }
  return new Set(found);
}

async function inspectTokens({ db }) {
  const ids = AUTHORIZED.tokenIds;
  const [snaps, referenced] = await Promise.all([
    Promise.all(ids.map((id) => db.collection('qrTokens').doc(id).get())),
    referencedTokenIds({ db, ids }),
  ]);
  const incluidos = [];
  const excluidos = [];
  snaps.forEach((s, i) => {
    const id = ids[i];
    const reasons = [];
    if (!s.exists) reasons.push('no existe (¿ya eliminado?)');
    else {
      if (s.get('usadoEn') != null) reasons.push('cambió de estado: ahora está usado');
      if (s.get('generadorUid')) reasons.push('pertenece al sistema nuevo (generadorUid)');
      if (referenced.has(id)) reasons.push('una asistencia lo referencia');
    }
    if (reasons.length) excluidos.push({ id, motivos: reasons });
    else {
      incluidos.push({
        id,
        tipo: s.get('tipo') ?? null,
        terminalId: s.get('terminalId') ?? null,
        creadoEn: iso(s.get('creadoEn')),
      });
    }
  });
  return { incluidos, excluidos };
}

async function inspectAudit({ db, terminalUids }) {
  const ids = AUTHORIZED.auditIds;
  const snaps = await Promise.all(ids.map((id) => db.collection('auditoria').doc(id).get()));
  const incluidos = [];
  const excluidos = [];
  snaps.forEach((s, i) => {
    const id = ids[i];
    if (!s.exists) {
      const nota = id.length !== 20
        ? `no existe; el id tiene ${id.length} caracteres y los de Firestore suelen tener 20 (¿error de transcripción?)`
        : 'no existe';
      excluidos.push({ id, motivos: [nota] });
      return;
    }
    const accion = s.get('accion');
    if (!TERMINAL_AUDIT_ACTIONS.includes(accion)) {
      excluidos.push({ id, motivos: [`la acción «${accion ?? '-'}» no es del sistema antiguo de terminales`] });
      return;
    }
    incluidos.push({
      id,
      accion,
      objetivo: s.get('objetivo') ?? null,
      objetivoEsTerminalAutorizada: terminalUids.has(s.get('objetivo')),
      creadoEn: iso(s.get('creadoEn')),
    });
  });
  return { incluidos, excluidos };
}

/** Elementos que no se tocan: se informan para dejar constancia. */
async function inspectRetained({ db }) {
  const [asistencias, usuarios, tokensTotal, nuevos, auditoriaTotal] = await Promise.all([
    db.collection('asistencias').count().get().then((s) => s.data().count),
    db.collection('usuarios').count().get().then((s) => s.data().count),
    db.collection('qrTokens').count().get().then((s) => s.data().count),
    db.collection('qrTokens').where('generadorUid', '>', '').count().get().then((s) => s.data().count),
    db.collection('auditoria').count().get().then((s) => s.data().count),
  ]);
  return { asistencias, usuarios, qrTokensTotal: tokensTotal, qrTokensSistemaNuevo: nuevos, auditoriaTotal };
}

async function collectPurgePlan({ auth, db, now = new Date() }) {
  const cuentas = [];
  for (const uid of AUTHORIZED.accountUids) cuentas.push(await inspectAccount({ auth, db, uid }));
  const includedUids = new Set(cuentas.filter((c) => c.incluida).map((c) => c.uid));

  const [terminales, terminalPruebas, tokens, auditoria, conservados] = await Promise.all([
    inspectCollection({ db, name: 'terminales', includedUids, expected: AUTHORIZED.expected.terminales }),
    inspectCollection({ db, name: 'terminalPruebas', includedUids, expected: AUTHORIZED.expected.terminalPruebas }),
    inspectTokens({ db }),
    inspectAudit({ db, terminalUids: new Set(AUTHORIZED.accountUids) }),
    inspectRetained({ db }),
  ]);

  const totales = {
    cuentasAuth: includedUids.size,
    terminales: terminales.incluidos.length,
    terminalPruebas: terminalPruebas.incluidos.length,
    qrTokens: tokens.incluidos.length,
    auditoria: auditoria.incluidos.length,
  };
  totales.general = Object.values(totales).reduce((a, b) => a + b, 0);

  const diferencias = [];
  for (const c of cuentas.filter((x) => !x.incluida)) {
    diferencias.push(`Cuenta ${c.uid} excluida: ${c.motivos.join('; ')}`);
  }
  for (const col of [terminales, terminalPruebas]) {
    if (col.incluidos.length !== col.esperados) {
      diferencias.push(`${col.coleccion}: se esperaban ${col.esperados} documentos y hay ${col.incluidos.length} incluibles`);
    }
    if (col.excluidos.length) {
      diferencias.push(`${col.coleccion}: ${col.excluidos.length} documento(s) fuera de la autorización (excluidos)`);
    }
  }
  if (tokens.excluidos.length) diferencias.push(`qrTokens: ${tokens.excluidos.length} excluido(s)`);
  if (auditoria.excluidos.length) diferencias.push(`auditoria: ${auditoria.excluidos.length} excluido(s)`);

  return {
    generado: now.toISOString(),
    cuentas, terminales, terminalPruebas, tokens, auditoria, conservados, totales, diferencias,
  };
}

const yesNo = (v) => (typeof v === 'boolean' ? (v ? 'sí' : 'no') : String(v));

function formatReport(plan, project) {
  const o = [];
  const t = plan.totales;
  o.push('SIMULACIÓN DE PURGA DEL SISTEMA ANTIGUO DE TERMINALES');
  o.push(`Proyecto Firebase verificado : ${project}`);
  o.push('Modo                         : SIMULACIÓN (solo lectura; no se elimina ni modifica nada)');
  o.push(`Generado                     : ${plan.generado}`);

  o.push('', '── A. Cuentas de Authentication ─────────────────────────');
  for (const c of plan.cuentas) {
    o.push(`${c.incluida ? 'INCLUIDA' : 'EXCLUIDA'}  UID ${c.uid}`);
    o.push(`  Terminal : ${c.nombre === null ? '(sin documento terminales/{uid})' : `"${c.nombre}"`}`);
    o.push(c.auth
      ? `  Auth     : ${c.auth.email} | deshabilitada=${yesNo(c.auth.deshabilitada)} | último acceso=${c.auth.ultimoAcceso ?? 'nunca'}`
      : '  Auth     : no existe');
    o.push('  Documentos asociados:');
    for (const [k, v] of Object.entries(c.documentosAsociados)) o.push(`    - ${k}: ${yesNo(v)}`);
    const r = c.referenciasQueSeConservan;
    o.push(`  Referencias que se conservan: asistencias(terminalId)=${r.asistenciasComoTerminal} auditoría(objetivo)=${r.auditoriaComoObjetivo} qrTokens(terminalId)=${r.qrTokensConTerminalId}`);
    c.motivos.forEach((m) => o.push(`  ✗ ${m}`));
  }
  o.push('Nota: terminalClaves y solicitudesEliminacionTerminal se muestran como asociados, pero NO están en la autorización (B) y no cuentan en los totales.');

  for (const col of [plan.terminales, plan.terminalPruebas]) {
    o.push('', `── B. ${col.coleccion} (total en la colección: ${col.total}, esperados: ${col.esperados}) ──`);
    col.incluidos.forEach((id) => o.push(`  incluido : ${col.coleccion}/${id}`));
    col.excluidos.forEach((x) => o.push(`  EXCLUIDO : ${col.coleccion}/${x.id} — ${x.motivo}`));
    col.faltantes.forEach((id) => o.push(`  FALTANTE : ${col.coleccion}/${id} (no existe)`));
  }

  o.push('', `── C. qrTokens antiguos sin usar (autorizados: ${AUTHORIZED.tokenIds.length}) ──`);
  plan.tokens.incluidos.forEach((x) => o.push(`  verificado : qrTokens/${x.id} tipo=${x.tipo ?? '-'} terminal=${x.terminalId ?? '-'} creado=${x.creadoEn ?? '-'}`));
  plan.tokens.excluidos.forEach((x) => o.push(`  EXCLUIDO   : qrTokens/${x.id} — ${x.motivos.join('; ')}`));

  o.push('', `── D. auditoria antigua (autorizados: ${AUTHORIZED.auditIds.length}) ──`);
  plan.auditoria.incluidos.forEach((x) => o.push(`  verificado : auditoria/${x.id} accion=${x.accion} objetivo=${x.objetivo ?? '-'} terminalAutorizada=${yesNo(x.objetivoEsTerminalAutorizada)} ${x.creadoEn ?? ''}`));
  plan.auditoria.excluidos.forEach((x) => o.push(`  EXCLUIDO   : auditoria/${x.id} — ${x.motivos.join('; ')}`));

  o.push('', '── Totales que serían afectados ─────────────────────────');
  o.push(`Cuentas de Authentication : ${t.cuentasAuth}`);
  o.push(`Documentos terminales     : ${t.terminales}`);
  o.push(`Documentos terminalPruebas: ${t.terminalPruebas}`);
  o.push(`qrTokens antiguos         : ${t.qrTokens}`);
  o.push(`Registros de auditoría    : ${t.auditoria}`);
  o.push(`TOTAL GENERAL             : ${t.general}`);

  const k = plan.conservados;
  o.push('', '── Se conservan (no se tocan) ───────────────────────────');
  o.push(`Asistencias: ${k.asistencias} (todas; también las que usan terminalId antiguo)`);
  o.push(`Perfiles en usuarios: ${k.usuarios} | cuentas normales: no incluidas`);
  o.push(`qrTokens: ${k.qrTokensTotal} en total, de los cuales ${k.qrTokensSistemaNuevo} del sistema nuevo (generadorUid) se conservan; también los usados y referenciados`);
  o.push(`Auditoría: ${k.auditoriaTotal} registros en total; solo los verificados de la sección D serían candidatos`);

  o.push('', '── Errores, faltantes y cambios respecto al inventario ───');
  if (plan.diferencias.length) plan.diferencias.forEach((d) => o.push(`  • ${d}`));
  else o.push('  Ninguno.');
  return o.join('\n');
}

module.exports = { AUTHORIZED, TERMINAL_AUDIT_ACTIONS, collectPurgePlan, formatReport };
