/**
 * Migración de costos de insumos a una colección protegida.
 *
 * Contexto: hasta ahora el costo de un insumo vivía en `insumos/{id}.costoUnitario`
 * y se repetía en los movimientos de tipo `compra`. Cocina lee ambos, así que
 * veía los costos. El diseño nuevo guarda el costo en `costosInsumos/{id}`
 * (solo Admin y Superadmin) y quita el campo de `insumos` y de los movimientos.
 *
 * Esta migración:
 *   1. COPIA cada `insumos/{id}.costoUnitario` a `costosInsumos/{id}` (solo crea;
 *      nunca sobrescribe un costo existente distinto: eso es un conflicto).
 *   2. VERIFICA cada movimiento de compra contra su línea en `compras`
 *      (mismo insumo y mismo costo). Si algo no cuadra, no cambia nada.
 *   3. RELEE las copias antes de quitar nada.
 *   4. QUITA únicamente el campo `costoUnitario` de `insumos` y de los
 *      movimientos de compra (con precondición de la última modificación leída:
 *      si alguien cambió el documento entretanto, esa operación falla).
 *   5. Deja una entrada en `auditoria`.
 *
 * Es idempotente y reanudable. No toca ningún otro campo ni documento. El único
 * cambio sobre documentos históricos es quitar ese campo duplicado: el valor
 * queda en `costosInsumos` y, para las compras, también en `compras.lineas`.
 *
 * Informa además (sin modificar) de las compras pendientes con más líneas que
 * el máximo nuevo: no podrían recibirse con las reglas nuevas.
 */
const COLLECTIONS = {
  insumos: 'insumos',
  costos: 'costosInsumos',
  movimientos: 'movimientosInventario',
  compras: 'compras',
  auditoria: 'auditoria',
};

const FIELD = 'costoUnitario';
const MAX_COST = 10000000; // S/ 100,000.00 por unidad, igual que las reglas
const MAX_PURCHASE_LINES = 5;
const CHUNK = 200;

const AUDIT_ACTOR_UID = 'script-local';
const AUDIT_ACTOR_NAME = 'Script administrativo local';
const AUDIT_ACTION = 'migrar_costos_insumos';
const COST_AUTHOR = 'migracion';

const State = Object.freeze({
  migrate: 'migrar',
  done: 'ya-migrado',
  blocked: 'bloqueada',
});

class MigrationError extends Error {
  /** @param progress lo que SÍ se llegó a hacer antes del fallo. */
  constructor(message, progress, cause) {
    super(message);
    this.name = 'MigrationError';
    this.progress = progress;
    this.cause = cause;
  }
}

const emptyProgress = () => ({
  copiados: 0,
  insumosLimpios: 0,
  movimientosLimpios: 0,
  auditoria: false,
});

const validCost = (v) => Number.isInteger(v) && v >= 0 && v <= MAX_COST;

/** Lee el estado actual sin modificar nada (simulación y comprobación previa). */
async function inspectMigration({ db }) {
  const [insumos, costos, withCost, compras] = await Promise.all([
    db.collection(COLLECTIONS.insumos).get(),
    db.collection(COLLECTIONS.costos).get(),
    // Movimientos que tienen el campo con un número. (Un valor no numérico no
    // aparece aquí; los movimientos de compra los validan las reglas.)
    db.collection(COLLECTIONS.movimientos).where(FIELD, '>=', 0).get(),
    db.collection(COLLECTIONS.compras).get(),
  ]);

  const conflicts = [];
  const costById = new Map(costos.docs.map((d) => [d.id, d.get(FIELD)]));
  const purchases = new Map(compras.docs.map((d) => [d.id, d.data()]));

  const toCopy = [];
  const insumosToStrip = [];
  let alreadyCopied = 0;
  for (const doc of insumos.docs) {
    const data = doc.data();
    if (!(FIELD in data)) continue;
    const value = data[FIELD];
    if (!validCost(value)) {
      conflicts.push(`insumos/${doc.id}: costo no válido (${JSON.stringify(value)}).`);
      continue;
    }
    insumosToStrip.push({ ref: doc.ref, id: doc.id, updateTime: doc.updateTime, cost: value });
    if (!costById.has(doc.id)) {
      toCopy.push({ id: doc.id, cost: value });
    } else if (costById.get(doc.id) !== value) {
      conflicts.push(
        `insumos/${doc.id}: ya existe costosInsumos/${doc.id} con un costo distinto ` +
          `(${costById.get(doc.id)} frente a ${value}).`);
    } else {
      alreadyCopied += 1;
    }
  }

  const movementsToStrip = [];
  for (const doc of withCost.docs) {
    const data = doc.data();
    if (data.tipo !== 'compra') {
      conflicts.push(`movimientosInventario/${doc.id}: tiene costo pero no es de compra (${data.tipo}).`);
      continue;
    }
    const purchase = purchases.get(data.compraId);
    const line = purchase && Array.isArray(purchase.lineas) && Number.isInteger(data.linea)
      ? purchase.lineas[data.linea]
      : undefined;
    if (!purchase) {
      conflicts.push(`movimientosInventario/${doc.id}: la compra ${data.compraId} no existe.`);
    } else if (!line) {
      conflicts.push(`movimientosInventario/${doc.id}: la línea ${data.linea} no existe en la compra.`);
    } else if (line.insumoId !== data.insumoId) {
      conflicts.push(`movimientosInventario/${doc.id}: el insumo no coincide con la línea de la compra.`);
    } else if (line[FIELD] !== data[FIELD]) {
      conflicts.push(
        `movimientosInventario/${doc.id}: el costo (${data[FIELD]}) no coincide con la ` +
          `línea de la compra (${line[FIELD]}).`);
    } else {
      movementsToStrip.push({ ref: doc.ref, id: doc.id, updateTime: doc.updateTime, cost: data[FIELD] });
    }
  }

  const oversizedPending = compras.docs
    .filter((d) => d.get('estado') === 'pendiente' && (d.get('lineas') ?? []).length > MAX_PURCHASE_LINES)
    .map((d) => d.id);

  const pending = toCopy.length + insumosToStrip.length + movementsToStrip.length;
  let state;
  if (conflicts.length) state = State.blocked;
  else if (pending === 0) state = State.done;
  else state = State.migrate;

  return {
    state,
    conflicts,
    toCopy,
    insumosToStrip,
    movementsToStrip,
    counts: {
      insumos: insumos.size,
      aCopiar: toCopy.length,
      yaCopiados: alreadyCopied,
      insumosALimpiar: insumosToStrip.length,
      movimientosALimpiar: movementsToStrip.length,
      conflictos: conflicts.length,
    },
    oversizedPending,
  };
}

async function eachChunk(items, fn) {
  for (let i = 0; i < items.length; i += CHUNK) await fn(items.slice(i, i + CHUNK));
}

/**
 * Ejecuta la migración. `FieldValue` se inyecta (como en los otros scripts).
 * Lanza `MigrationError` con el progreso real si algo falla; repetir completa.
 */
async function executeMigration({ db, FieldValue }) {
  const report = await inspectMigration({ db });
  if (report.state === State.blocked) {
    throw new MigrationError(report.conflicts.join(' '), emptyProgress());
  }
  const progress = emptyProgress();
  if (report.state === State.done) return { report, progress };

  try {
    await eachChunk(report.toCopy, async (chunk) => {
      const batch = db.batch();
      for (const { id, cost } of chunk) {
        // `create` falla si alguien creó el documento entretanto: nunca pisa.
        batch.create(db.collection(COLLECTIONS.costos).doc(id), {
          [FIELD]: cost,
          actualizadoEn: FieldValue.serverTimestamp(),
          actualizadoPor: COST_AUTHOR,
        });
      }
      await batch.commit();
      progress.copiados += chunk.length;
    });
  } catch (e) {
    throw new MigrationError(`No se pudieron copiar los costos: ${e.message}`, progress, e);
  }

  // Antes de quitar nada se comprueba que cada costo quedó copiado tal cual.
  try {
    const source = await Promise.all(
      report.insumosToStrip.map((s) => s.ref.get().then((d) => [s.id, d.get(FIELD)])));
    const copies = await Promise.all(
      source.map(([id]) => db.collection(COLLECTIONS.costos).doc(id).get()));
    source.forEach(([id, value], i) => {
      if (copies[i].get(FIELD) !== value) {
        throw new Error(`la copia de costosInsumos/${id} no coincide con el insumo`);
      }
    });
  } catch (e) {
    throw new MigrationError(`Verificación de las copias fallida: ${e.message}`, progress, e);
  }

  const strip = async (items, counter, label) => {
    try {
      await eachChunk(items, async (chunk) => {
        const batch = db.batch();
        for (const { ref, updateTime } of chunk) {
          // Solo se borra este campo, y solo si el documento sigue como se leyó.
          batch.update(ref, { [FIELD]: FieldValue.delete() }, { lastUpdateTime: updateTime });
        }
        await batch.commit();
        progress[counter] += chunk.length;
      });
    } catch (e) {
      throw new MigrationError(`No se pudo quitar el costo de ${label}: ${e.message}`, progress, e);
    }
  };
  await strip(report.insumosToStrip, 'insumosLimpios', 'los insumos');
  await strip(report.movementsToStrip, 'movimientosLimpios', 'los movimientos de compra');

  try {
    await db.collection(COLLECTIONS.auditoria).doc().set({
      accion: AUDIT_ACTION,
      actorUid: AUDIT_ACTOR_UID,
      actorNombre: AUDIT_ACTOR_NAME,
      objetivo: COLLECTIONS.insumos,
      campos: [
        `costos copiados: ${progress.copiados}`,
        `insumos limpiados: ${progress.insumosLimpios}`,
        `movimientos de compra limpiados: ${progress.movimientosLimpios}`,
      ],
      creadoEn: FieldValue.serverTimestamp(),
    });
    progress.auditoria = true;
  } catch (e) {
    throw new MigrationError(`No se pudo registrar la auditoría: ${e.message}`, progress, e);
  }
  return { report, progress };
}

module.exports = {
  AUDIT_ACTION,
  COLLECTIONS,
  MAX_PURCHASE_LINES,
  MigrationError,
  State,
  executeMigration,
  inspectMigration,
};
