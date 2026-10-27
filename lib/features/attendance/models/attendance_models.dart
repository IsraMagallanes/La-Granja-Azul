import 'package:equatable/equatable.dart';

DateTime? _toDate(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw == null) return null;
  try {
    // Timestamp de Firestore (duck-typing: el modelo no depende de Firebase).
    final date = (raw as dynamic).toDate();
    return date is DateTime ? date : null;
  } on NoSuchMethodError {
    return null;
  }
}

enum PunchType {
  entrada('entrada', 'Entrada'),
  salida('salida', 'Salida');

  const PunchType(this.value, this.label);

  final String value;
  final String label;

  static PunchType? tryParse(Object? raw) {
    for (final type in values) {
      if (type.value == raw) return type;
    }
    return null;
  }
}

/// Token efímero de un QR (`qrTokens/{id}`). El QR solo contiene su id.
class QrToken extends Equatable {
  const QrToken({
    required this.id,
    required this.uid,
    required this.tipo,
    required this.nombreMostrar,
    required this.creadoEn,
    required this.usadoEn,
  });

  /// Vigencia del QR; debe coincidir con `firestore.rules`.
  static const lifetime = Duration(seconds: 45);

  final String id;
  final String uid;
  final PunchType tipo;
  final String nombreMostrar;
  final DateTime? creadoEn;
  final DateTime? usadoEn;

  bool get used => usadoEn != null;

  static QrToken? fromMap(String id, Map<String, dynamic> data) {
    final tipo = PunchType.tryParse(data['tipo']);
    final uid = data['uid'];
    if (tipo == null || uid is! String) return null;
    return QrToken(
      id: id,
      uid: uid,
      tipo: tipo,
      nombreMostrar: (data['nombreMostrar'] as String?) ?? '',
      creadoEn: _toDate(data['creadoEn']),
      usadoEn: _toDate(data['usadoEn']),
    );
  }

  @override
  List<Object?> get props => [id, uid, tipo, nombreMostrar, creadoEn, usadoEn];
}

/// Estado de jornada de un trabajador (`estadoAsistencia/{uid}`).
class AttendanceState extends Equatable {
  const AttendanceState({required this.abierta, this.asistenciaId});

  final bool abierta;
  final String? asistenciaId;

  static AttendanceState fromMap(Map<String, dynamic> data) => AttendanceState(
        abierta: data['abierta'] == true,
        asistenciaId: data['asistenciaId'] as String?,
      );

  @override
  List<Object?> get props => [abierta, asistenciaId];
}

enum AttendanceOrigin {
  qr('qr', 'QR'),
  regularizada('regularizada', 'Regularizada'),
  supervisada('supervisada', 'Supervisada');

  const AttendanceOrigin(this.value, this.label);

  final String value;
  final String label;

  static AttendanceOrigin tryParse(Object? raw) {
    for (final origin in values) {
      if (origin.value == raw) return origin;
    }
    return qr;
  }
}

/// Jornada: una entrada y, al cerrarse, una salida (`asistencias/{id}`).
class AttendanceRecord extends Equatable {
  const AttendanceRecord({
    required this.id,
    required this.uid,
    required this.entrada,
    this.salida,
    this.origen = AttendanceOrigin.qr,
    this.regularizada = false,
    this.motivo,
  });

  final String id;
  final String uid;
  final DateTime entrada;
  final DateTime? salida;
  final AttendanceOrigin origen;
  final bool regularizada;

  /// Solo en registros regularizados.
  final String? motivo;

  bool get abierta => salida == null;

  Duration? get duracion => salida?.difference(entrada);

  static AttendanceRecord? fromMap(String id, Map<String, dynamic> data) {
    final entrada = _toDate(data['entrada']);
    final uid = data['uid'];
    if (entrada == null || uid is! String) return null;
    return AttendanceRecord(
      id: id,
      uid: uid,
      entrada: entrada,
      salida: _toDate(data['salida']),
      origen: AttendanceOrigin.tryParse(data['origen']),
      regularizada: data['regularizada'] == true,
      motivo: data['motivo'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [id, uid, entrada, salida, origen, regularizada, motivo];
}

/// Terminal autorizada (`terminales/{uid}`).
class AttendanceTerminal extends Equatable {
  const AttendanceTerminal({
    required this.uid,
    required this.nombre,
    required this.activo,
  });

  final String uid;
  final String nombre;
  final bool activo;

  static AttendanceTerminal fromMap(String uid, Map<String, dynamic> data) =>
      AttendanceTerminal(
        uid: uid,
        nombre: (data['nombre'] as String?) ?? '',
        activo: data['activo'] == true,
      );

  @override
  List<Object?> get props => [uid, nombre, activo];
}

enum CorrectionStatus {
  pendiente('pendiente', 'Pendiente'),
  aprobada('aprobada', 'Aprobada'),
  rechazada('rechazada', 'Rechazada');

  const CorrectionStatus(this.value, this.label);

  final String value;
  final String label;

  static CorrectionStatus tryParse(Object? raw) {
    for (final status in values) {
      if (status.value == raw) return status;
    }
    return pendiente;
  }
}

/// Solicitud de corrección de un trabajador (`correcciones/{id}`).
class CorrectionRequest extends Equatable {
  const CorrectionRequest({
    required this.id,
    required this.uid,
    required this.fecha,
    required this.tipo,
    required this.motivo,
    required this.estado,
    this.respuesta,
  });

  final String id;
  final String uid;
  final String fecha;
  final String tipo;
  final String motivo;
  final CorrectionStatus estado;
  final String? respuesta;

  static CorrectionRequest fromMap(String id, Map<String, dynamic> d) =>
      CorrectionRequest(
        id: id,
        uid: (d['uid'] as String?) ?? '',
        fecha: (d['fecha'] as String?) ?? '',
        tipo: (d['tipo'] as String?) ?? '',
        motivo: (d['motivo'] as String?) ?? '',
        estado: CorrectionStatus.tryParse(d['estado']),
        respuesta: d['respuesta'] as String?,
      );

  @override
  List<Object?> get props => [id, uid, fecha, tipo, motivo, estado, respuesta];
}
