/**
 * Inventario de perfiles con el rol Almacén (rol que se va a retirar). SOLO
 * LECTURA: no modifica usuarios, Authentication ni Firestore (únicamente `get`,
 * consultas `where` / `count` y `getUser`).
 *
 * No expone datos personales sensibles: omite documento, celular, apellidos y
 * correo completo (el correo sale enmascarado). Sí muestra UID, nombres de pila,
 * estado, fechas, jornada y cuántos registros históricos referencian a cada
 * perfil, para decidir uno por uno qué hacer. No decide ni reasigna nada.
 */
const { countWhere } = require('./terminal_criteria');

const KNOWN_ROLES = ['superadmin', 'admin', 'mesero', 'cocina', 'cajero', 'almacen'];

const mask = (email = '') => email.replace(/^(.{2}).*(@.*)$/, '$1•••$2');
const iso = (v) => v?.toDate?.().toISOString() ?? null;

async function findAuthUser(auth, uid) {
  try {
    return await auth.getUser(uid);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') return null;
    throw e;
  }
}

/** Cuántos registros históricos apuntan a este UID (nada se modifica). */
async function countReferences(db, uid) {
  const c = (col, field, value = uid) => countWhere(db, col, field, value);
  const [movimientos, comprasCreadas, comprasRecibidas, comprasCanceladas, comprasPendientes,
    recetas, asistencias, correcciones, auditoriaActor, auditoriaObjetivo, movimientosPersonal,
    regularizadas, tokens] = await Promise.all([
    c('movimientosInventario', 'creadoPor'),
    c('compras', 'creadoPor'),
    c('compras', 'recibidoPor'),
    c('compras', 'canceladoPor'),
    db.collection('compras').where('creadoPor', '==', uid).where('estado', '==', 'pendiente')
      .count().get().then((s) => s.data().count),
    c('recetas', 'actualizadoPor'),
    c('asistencias', 'uid'),
    c('correcciones', 'uid'),
    c('auditoria', 'actorUid'),
    c('auditoria', 'objetivo'),
    c('movimientosPersonal', 'uid'),
    c('asistencias', 'regularizadoPor'),
    c('qrTokens', 'uid'),
  ]);
  return {
    movimientosInventario: movimientos,
    comprasCreadas, comprasRecibidas, comprasCanceladas, comprasPendientesCreadas: comprasPendientes,
    recetasActualizadas: recetas,
    asistencias, correccionesSolicitadas: correcciones, asistenciasRegularizadasPorEl: regularizadas,
    auditoriaComoActor: auditoriaActor, auditoriaComoObjetivo: auditoriaObjetivo,
    movimientosDePersonal: movimientosPersonal, qrTokens: tokens,
  };
}

async function inspectProfile({ auth, db, snap }) {
  const uid = snap.id;
  const d = snap.data();
  const [authUser, stateSnap, references] = await Promise.all([
    findAuthUser(auth, uid),
    db.collection('estadoAsistencia').doc(uid).get(),
    countReferences(db, uid),
  ]);
  return {
    uid,
    nombres: typeof d.nombres === 'string' ? d.nombres : null,
    rol: d.rol,
    estado: d.estado ?? null,
    activo: d.activo === true,
    bajaTipo: d.bajaTipo ?? null,
    fechaIngreso: d.fechaIngreso ?? null,
    creadoEn: iso(d.creadoEn),
    activadoEn: iso(d.activadoEn),
    horarioAsignado: Boolean(d.horarioId),
    jornada: stateSnap.exists
      ? {
          abierta: stateSnap.get('abierta') === true,
          actualizadoEn: iso(stateSnap.get('actualizadoEn')),
        }
      : { abierta: false, actualizadoEn: null },
    auth: authUser
      ? {
          email: mask(authUser.email ?? ''),
          emailVerified: authUser.emailVerified,
          disabled: authUser.disabled,
          ultimoAcceso: authUser.metadata?.lastSignInTime ?? null,
        }
      : null,
    referencias: references,
  };
}

async function collectAlmacenInventory({ auth, db, now = new Date() }) {
  const roles = await db.collection('usuarios').select('rol').get();
  const byRole = {};
  const almacen = [];
  const unknown = [];
  for (const doc of roles.docs) {
    const rol = doc.get('rol');
    const key = typeof rol === 'string' ? rol : '(sin rol)';
    byRole[key] = (byRole[key] ?? 0) + 1;
    if (rol === 'almacen') almacen.push(doc.id);
    // Variantes de escritura de Almacén o roles inválidos: la app los descartaría
    // igual que a «almacen» al retirar el rol, así que se listan aparte.
    else if (!KNOWN_ROLES.includes(rol)) {
      unknown.push({
        uid: doc.id,
        rol: key,
        pareceAlmacen: typeof rol === 'string' && rol.trim().toLowerCase().startsWith('almac'),
      });
    }
  }

  const profiles = [];
  for (const uid of almacen.sort()) {
    profiles.push(await inspectProfile({
      auth, db, snap: await db.collection('usuarios').doc(uid).get(),
    }));
  }
  const by = (fn) => profiles.filter(fn).length;
  return {
    generado: now.toISOString(),
    resumen: {
      perfilesTotal: roles.size,
      porRol: byRole,
      almacen: profiles.length,
      almacenActivos: by((p) => p.activo),
      almacenInactivos: by((p) => !p.activo),
      conJornadaAbierta: by((p) => p.jornada.abierta),
      sinActivar: by((p) => !p.activadoEn),
      sinCuentaAuth: by((p) => !p.auth),
      conComprasPendientes: by((p) => p.referencias.comprasPendientesCreadas > 0),
      rolesDesconocidos: unknown.length,
    },
    perfiles: profiles,
    rolesDesconocidos: unknown,
  };
}

const yesNo = (v) => (v ? 'sí' : 'no');

function formatReport(inv, project) {
  const out = [];
  const r = inv.resumen;
  out.push(`Proyecto : ${project}`);
  out.push('Modo     : SOLO LECTURA (no se modifica ningún perfil, cuenta ni dato)');
  out.push(`Generado : ${inv.generado}`);
  out.push('');
  out.push(`Perfiles en usuarios : ${r.perfilesTotal}  (${Object.entries(r.porRol).map(([k, v]) => `${k}=${v}`).join(', ')})`);
  out.push(`Perfiles Almacén     : ${r.almacen} (activos ${r.almacenActivos}, inactivos ${r.almacenInactivos})`);
  out.push(`  con jornada abierta: ${r.conJornadaAbierta} | sin activar: ${r.sinActivar} | sin cuenta Auth: ${r.sinCuentaAuth} | con compras pendientes: ${r.conComprasPendientes}`);
  out.push(`Roles desconocidos   : ${r.rolesDesconocidos}`);
  for (const p of inv.perfiles) {
    const x = p.referencias;
    out.push('');
    out.push('── PERFIL ALMACÉN ──────────────────────────────');
    out.push(`UID        : ${p.uid}`);
    out.push(`Nombres    : ${p.nombres ?? '(sin dato)'}`);
    out.push(`Estado     : ${p.estado ?? '(sin estado)'} | activo=${yesNo(p.activo)}${p.bajaTipo ? ` | baja=${p.bajaTipo}` : ''}`);
    out.push(`Fechas     : ingreso=${p.fechaIngreso ?? '-'} | creado=${p.creadoEn ?? '-'} | activado=${p.activadoEn ?? 'pendiente'}`);
    out.push(`Jornada    : ${p.jornada.abierta ? 'ABIERTA' : 'cerrada'}${p.jornada.actualizadoEn ? ` (desde ${p.jornada.actualizadoEn})` : ''} | horario asignado=${yesNo(p.horarioAsignado)}`);
    out.push(p.auth
      ? `Auth       : ${p.auth.email} | verificado=${yesNo(p.auth.emailVerified)} | deshabilitada=${yesNo(p.auth.disabled)} | último acceso=${p.auth.ultimoAcceso ?? 'nunca'}`
      : 'Auth       : no existe cuenta de Authentication');
    out.push(`Inventario : movimientos=${x.movimientosInventario} recetas=${x.recetasActualizadas} compras creadas=${x.comprasCreadas} (pendientes ${x.comprasPendientesCreadas}) recibidas=${x.comprasRecibidas} canceladas=${x.comprasCanceladas}`);
    out.push(`Asistencia : registros=${x.asistencias} correcciones=${x.correccionesSolicitadas} regularizadas por él=${x.asistenciasRegularizadasPorEl} qrTokens=${x.qrTokens}`);
    out.push(`Auditoría  : como actor=${x.auditoriaComoActor} como objetivo=${x.auditoriaComoObjetivo} | movimientos de personal=${x.movimientosDePersonal}`);
  }
  if (inv.rolesDesconocidos.length) {
    out.push('');
    out.push('── PERFILES CON ROL NO RECONOCIDO (revisar) ──────────');
    for (const u of inv.rolesDesconocidos) {
      out.push(`${u.uid}  rol="${u.rol}"${u.pareceAlmacen ? '  ← parece una variante de Almacén' : ''}`);
    }
  }
  out.push('');
  out.push('Los movimientos, compras y auditorías guardan uid y nombre copiados (no el rol): cambiar o dar de baja un perfil no los altera.');
  return out.join('\n');
}

module.exports = { collectAlmacenInventory, formatReport };
