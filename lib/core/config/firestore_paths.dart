/// Nombres de colecciones de Firestore.
abstract final class FirestorePaths {
  static const usuarios = 'usuarios';
  static const carta = 'carta';

  static const categorias = 'categorias';

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
  static const qrTokens = 'qrTokens';
  static const asistencias = 'asistencias';
  static const estadoAsistencia = 'estadoAsistencia';
  static const correcciones = 'correcciones';

}
