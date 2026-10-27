/// Nombres de colecciones de Firestore.
abstract final class FirestorePaths {
  static const usuarios = 'usuarios';
  static const carta = 'carta';

  // Personal.
  static const documentos = 'documentos'; // índice único por documento
  static const correos = 'correos'; // índice único por correo
  static const movimientos = 'movimientosPersonal'; // motivos confidenciales
  static const restricciones = 'restricciones';
  static const auditoria = 'auditoria';

  // Asistencia.
  static const horarios = 'horarios';
  static const terminales = 'terminales';
  static const terminalClaves = 'terminalClaves'; // secreto del dispositivo
  static const terminalPruebas = 'terminalPruebas'; // prueba por marcación
  static const qrTokens = 'qrTokens';
  static const asistencias = 'asistencias';
  static const estadoAsistencia = 'estadoAsistencia';
  static const correcciones = 'correcciones';
}
