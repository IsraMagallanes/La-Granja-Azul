import 'package:equatable/equatable.dart';

/// Registro inmutable de una acción administrativa (`auditoria/{id}`).
/// Guarda quién, cuándo, qué y qué campos cambiaron; nunca los motivos
/// confidenciales ni los valores de datos personales.
class AuditEntry extends Equatable {
  const AuditEntry({
    required this.id,
    required this.accion,
    required this.actorUid,
    required this.actorNombre,
    required this.objetivo,
    required this.creadoEn,
    this.campos = const [],
  });

  final String id;
  final String accion;
  final String actorUid;
  final String actorNombre;

  /// UID, documento o identificador de lo afectado.
  final String objetivo;
  final DateTime? creadoEn;
  final List<String> campos;

  static AuditEntry fromMap(String id, Map<String, dynamic> data) {
    DateTime? when;
    try {
      when = (data['creadoEn'] as dynamic)?.toDate() as DateTime?;
    } on NoSuchMethodError {
      when = null;
    }
    return AuditEntry(
      id: id,
      accion: (data['accion'] as String?) ?? '',
      actorUid: (data['actorUid'] as String?) ?? '',
      actorNombre: (data['actorNombre'] as String?) ?? '',
      objetivo: (data['objetivo'] as String?) ?? '',
      creadoEn: when,
      campos: [for (final c in (data['campos'] as List?) ?? const []) '$c'],
    );
  }

  @override
  List<Object?> get props =>
      [id, accion, actorUid, actorNombre, objetivo, creadoEn, campos];
}

/// Acciones auditadas (valor guardado en `accion`).
abstract final class AuditAction {
  static const crearTrabajador = 'crear_trabajador';
  static const editarTrabajador = 'editar_trabajador';
  static const cambiarEstado = 'cambiar_estado';
  static const autorizarRegularizar = 'autorizar_regularizar';
  static const crearRestriccion = 'crear_restriccion';
  static const levantarRestriccion = 'levantar_restriccion';
  static const autorizarTerminal = 'autorizar_terminal';
  static const revocarTerminal = 'revocar_terminal';
  static const restablecerTerminal = 'restablecer_terminal';
  static const guardarHorario = 'guardar_horario';
  static const regularizarAsistencia = 'regularizar_asistencia';
  static const resolverCorreccion = 'resolver_correccion';
}
