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
  static const terminales = 'terminales';
  static const terminalClaves = 'terminalClaves';
  static const terminalPruebas = 'terminalPruebas';
  static const solicitudesEliminacionTerminal =
      'solicitudesEliminacionTerminal';
  static const qrTokens = 'qrTokens';
  static const asistencias = 'asistencias';
  static const estadoAsistencia = 'estadoAsistencia';
  static const correcciones = 'correcciones';
}
