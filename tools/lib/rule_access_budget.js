/**
 * Presupuesto de accesos a documentos de las reglas de seguridad (get, exists,
 * getAfter). Firestore admite 10 accesos por petición de un documento y 20 por
 * petición de varios documentos (lote o transacción). El emulador NO aplica esos
 * límites, así que aquí se calculan a partir de la estructura de las reglas y se
 * contrastan con un proyecto Firebase separado (tools/limits_probe.js).
 *
 * Criterio conservador: get() y getAfter() del MISMO documento cuentan por
 * separado (Firestore puede contarlos una sola vez; el resultado real puede ser
 * menor, nunca mayor). Cada fila lista los documentos distintos que las reglas
 * consultan en ese lote.
 */
const LIMIT_SINGLE = 10;
const LIMIT_BATCH = 20;

/** Recibir una compra de [n] líneas (Admin/Superadmin), opción B. */
function receivePurchase(n) {
  return {
    scenario: `Recibir una compra de ${n} línea(s)`,
    limit: LIMIT_BATCH,
    docs: {
      'usuarios/{admin} (rol, perfil activo, nombre)': 1,
      'compras/{id} (get antes + getAfter después)': 2,
      'movimientosInventario/{id}_{n} (getAfter, compartido)': n,
      'insumos/{id} (getAfter del insumo de cada línea)': n,
      'costosInsumos/{id} (getAfter: costo de cada línea)': n,
    },
  };
}

/** Entrega de utensilios por un Mesero (utensilio + asignación + movimiento). */
function utensilDelivery() {
  return {
    scenario: 'Entrega de utensilios por un Mesero',
    limit: LIMIT_BATCH,
    docs: {
      'usuarios/{mesero} (rol, perfil, nombre)': 1,
      'estadoAsistencia/{mesero} (jornada abierta)': 1,
      'usuarios/{destinatario} (rol mesero, activo, nombre)': 1,
      'utensilios/{id} (getAfter en el movimiento)': 1,
      'asignacionesUtensilios/{id} (getAfter en el movimiento)': 1,
      'movimientosUtensilios/{id} (getAfter en utensilio y asignación)': 1,
    },
  };
}

/** Alta o edición del catálogo con costo nuevo (Admin): utensilio + costo + auditoría. */
function utensilCatalogEdit() {
  return {
    scenario: 'Editar el catálogo de utensilios con costo nuevo',
    limit: LIMIT_BATCH,
    docs: {
      'usuarios/{admin}': 1,
      'auditoria/{id} (getAfter)': 1,
      'costosUtensilios/{id}_{n} (existsAfter)': 1,
      'utensilios/{id} (getAfter desde el costo)': 1,
    },
  };
}

/**
 * Cocina marca «Listo» y descuenta [n] insumos (Fase 8B). Tras la optimización de la
 * Etapa 1: el pedido ya no se lee antes (listoEn == request.time) y el paso a «Listo»
 * consulta solo el último movimiento (cadena). Antes: 5 + 2n y 3 + n por la operación del pedido.
 */
function kitchenReady(n) {
  return {
    scenario: `Cocina marca «Listo» y descuenta ${n} insumo(s) (Fase 8B)`,
    limit: LIMIT_BATCH,
    docs: {
      'usuarios/{cocina}': 1,
      'estadoAsistencia/{cocina}': 1,
      'pedidos/{id} (getAfter: estado y listoEn)': 1,
      'descuentosInventario/{id} (getAfter)': 1,
      'movimientosInventario/{id}_{n} (getAfter, existsAfter en cadena)': n,
      'insumos/{id} (getAfter)': n,
    },
  };
}

/** Accesos de CADA operación del lote «Listo» (límite de 10 por operación). */
function kitchenReadyPerOperation(n) {
  return {
    'pedido → listo': 4, // perfil, jornada, descuento, último movimiento
    'descuento (marcador)': 4, // perfil, jornada, pedido, (excepción)
    'movimiento de consumo': 5, // perfil, jornada, insumo, descuento, movimiento anterior
    'insumo (stock)': 4, // perfil, jornada, su movimiento, (n no influye)
    n,
  };
}

/** Edición de un insumo suelto (una sola escritura de un documento). */
function supplyEdit() {
  return {
    scenario: 'Editar un insumo (una sola escritura)',
    limit: LIMIT_SINGLE,
    docs: { 'usuarios/{usuario}': 1, 'estadoAsistencia/{usuario}': 1 },
  };
}

/** Fijar el costo de un insumo (una sola escritura de Admin). */
function supplyCostWrite() {
  return { scenario: 'Fijar el costo de un insumo', limit: LIMIT_SINGLE, docs: { 'usuarios/{admin}': 1 } };
}

const total = (s) => Object.values(s.docs).reduce((a, b) => a + b, 0);

/** Mayor número de líneas de compra que cabe en el límite por lote. */
function maxPurchaseLines() {
  let n = 1;
  while (total(receivePurchase(n + 1)) <= LIMIT_BATCH) n += 1;
  return n;
}

module.exports = {
  LIMIT_BATCH,
  LIMIT_SINGLE,
  kitchenReady,
  kitchenReadyPerOperation,
  maxPurchaseLines,
  receivePurchase,
  supplyCostWrite,
  supplyEdit,
  total,
  utensilCatalogEdit,
  utensilDelivery,
};
