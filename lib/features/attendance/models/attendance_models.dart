import 'package:equatable/equatable.dart';

import '../../roles/models/user_role.dart';

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

/// Token efímero de un QR de asistencia (`qrTokens/{id}`). Lo genera un
/// Superadmin, Admin o Cajero y lo escanea el personal; el QR solo contiene su
/// id. No identifica a quien escanea: la entrada o salida es de quien lo lee.
class QrToken extends Equatable {
  const QrToken({
    required this.id,
    required this.generadorUid,
    required this.generadorRol,
    required this.nombreMostrar,
    required this.creadoEn,
  });

  /// Vigencia del QR; debe coincidir con `firestore.rules`.
  static const lifetime = Duration(seconds: 45);

  final String id;
  final String generadorUid;
  final UserRole generadorRol;
  final String nombreMostrar;
  final DateTime? creadoEn;

  /// ¿Venció a la hora [now]? (Informativo: la vigencia real la decide el
  /// servidor.)
  bool isExpiredAt(DateTime now) =>
      creadoEn == null || !creadoEn!.add(lifetime).isAfter(now);

  static QrToken? fromMap(String id, Map<String, dynamic> data) {
    final rol = UserRole.tryParse(data['generadorRol']);
    final uid = data['generadorUid'];
    if (rol == null || uid is! String) return null;
    return QrToken(
      id: id,
      generadorUid: uid,
      generadorRol: rol,
      nombreMostrar: (data['nombreMostrar'] as String?) ?? '',
      creadoEn: _toDate(data['creadoEn']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    generadorUid,
    generadorRol,
    nombreMostrar,
    creadoEn,
  ];
}

/// Estado de jornada de un trabajador (`estadoAsistencia/{uid}`).
class AttendanceState extends Equatable {
  const AttendanceState({
    required this.abierta,
    this.asistenciaId,
    this.tokenId,
  });

  final bool abierta;
  final String? asistenciaId;

  /// Último QR con el que este trabajador marcó (no se encadena dos veces).
  final String? tokenId;

  static AttendanceState fromMap(Map<String, dynamic> data) => AttendanceState(
    abierta: data['abierta'] == true,
    asistenciaId: data['asistenciaId'] as String?,
    tokenId: data['tokenId'] as String?,
  );

  @override
  List<Object?> get props => [abierta, asistenciaId, tokenId];
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
  List<Object?> get props => [
    id,
    uid,
    entrada,
    salida,
    origen,
    regularizada,
    motivo,
  ];
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
