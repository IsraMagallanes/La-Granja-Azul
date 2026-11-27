/// Nombres de colecciones de Firestore.
abstract final class FirestorePaths {
  static const mesas = 'mesas';
  static const pedidos = 'pedidos';
  static const usuarios = 'usuarios';
  static const carta = 'carta';

  // Inventario (Fase 7 y 8B).
  static const insumos = 'insumos';
  static const recetas = 'recetas';
  static const movimientosInventario = 'movimientosInventario';
  static const descuentosInventario = 'descuentosInventario';
  static const excepcionesInventario = 'excepcionesInventario';
  static const costosInsumos = 'costosInsumos';

  // Utensilios (independiente de los insumos).
  static const utensilios = 'utensilios';
  static const directorioMeseros = 'directorioMeseros';
  static const asignacionesUtensilios = 'asignacionesUtensilios';
  static const movimientosUtensilios = 'movimientosUtensilios';
  static const costosUtensilios = 'costosUtensilios';

  static const categorias = 'categorias';
  static const cartaFotos = 'cartaFotos';
  static const reservaciones = 'reservaciones';
  static const pagos = 'pagos';
  static const cajas = 'cajas';
  static const cajaActiva = 'cajaActiva';
  static const movimientosCaja = 'movimientosCaja';

  // Personal.
  static const documentos = 'documentos';
  static const correos = 'correos';
  static const movimientos = 'movimientosPersonal';
  static const restricciones = 'restricciones';
  static const auditoria = 'auditoria';

  // Asistencia.
  static const horarios = 'horarios';
  static const qrTokens = 'qrTokens';
  static const asistencias = 'asistencias';
  static const estadoAsistencia = 'estadoAsistencia';
  static const correcciones = 'correcciones';
}
