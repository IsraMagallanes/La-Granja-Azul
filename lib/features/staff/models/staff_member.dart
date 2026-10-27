import 'package:equatable/equatable.dart';

import '../../roles/models/user_role.dart';
import '../../users/models/app_user.dart' show toDateOrNull;
import 'document_type.dart';
import 'staff_status.dart';

/// Ficha completa de un trabajador (documento `usuarios/{uid}`).
class StaffMember extends Equatable {
  const StaffMember({
    required this.uid,
    required this.nombres,
    required this.apellidos,
    required this.documentType,
    required this.documento,
    required this.email,
    required this.celular,
    required this.role,
    required this.estado,
    required this.fechaIngreso,
    this.celularAlterno,
    this.horarioId,
    this.puedeRegularizar = false,
    this.bajaTipo,
    this.activadoEn,
  });

  final String uid;
  final String nombres;
  final String apellidos;
  final DocumentType documentType;
  final String documento;
  final String email;

  /// 9 dígitos, sin el prefijo +51.
  final String celular;
  final String? celularAlterno;
  final UserRole role;
  final StaffStatus estado;
  final DateTime fechaIngreso;
  final String? horarioId;
  final bool puedeRegularizar;

  /// Tipo (no el texto confidencial) del último retiro o suspensión.
  final LeaveReason? bajaTipo;

  /// Primera entrada con correo verificado; `null` mientras no la haya hecho.
  final DateTime? activadoEn;

  /// Cuenta habilitada pero que el trabajador aún no activó (definir contraseña
  /// y verificar el correo). Que se haya enviado el correo NO la activa.
  bool get pendienteActivacion => estado == StaffStatus.activo && activadoEn == null;

  String get nombreCompleto => '$nombres $apellidos';
  bool get activo => estado.canAccess;

  /// Documento parcialmente oculto para listados.
  String get documentoEnmascarado => maskDocument(documento);

  String get celularEnmascarado => maskPhone(celular);

  static String maskDocument(String value) => value.length <= 4
      ? value
      : '${value.substring(0, 2)}${'•' * (value.length - 4)}${value.substring(value.length - 2)}';

  static String maskPhone(String value) => value.length < 9
      ? value
      : '${'•' * 6}${value.substring(6)}';

  /// Perfil creado antes de la Fase 3 (solo correo, nombre, rol y activo):
  /// se lista, pero sin documento ni celular hasta completarlo con
  /// `tools/complete_superadmin.js`.
  bool get incompleto => documento.isEmpty;

  /// `null` solo si el rol es inválido. Los perfiles de la Fase 2 (sin
  /// documento) se conservan como [incompleto] en lugar de ocultarse.
  static StaffMember? fromMap(String uid, Map<String, dynamic> data) {
    final role = UserRole.tryParse(data['rol']);
    if (role == null) return null;
    final type = DocumentType.tryParse(data['tipoDocumento']) ?? DocumentType.dni;
    final doc = data['numeroDocumento'] is String ? data['numeroDocumento'] as String : '';
    final legacyName = ((data['nombre'] as String?) ?? '').trim();
    final estado = StaffStatus.tryParse(data['estado']) ??
        (data['activo'] == true ? StaffStatus.activo : StaffStatus.baja);
    return StaffMember(
      uid: uid,
      nombres: (data['nombres'] as String?) ?? legacyName,
      apellidos: (data['apellidos'] as String?) ?? '',
      documentType: type,
      documento: doc,
      email: (data['email'] as String?) ?? '',
      celular: (data['celular'] as String?) ?? '',
      celularAlterno: data['celularAlterno'] as String?,
      role: role,
      estado: estado,
      fechaIngreso: _date(data['fechaIngreso']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      horarioId: data['horarioId'] as String?,
      puedeRegularizar: data['puedeRegularizar'] == true,
      bajaTipo: LeaveReason.tryParse(data['bajaTipo']),
      activadoEn: toDateOrNull(data['activadoEn']),
    );
  }

  /// Fecha de calendario guardada como texto `yyyy-MM-dd` (sin zona horaria).
  static DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

  static String formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  List<Object?> get props => [
        uid,
        nombres,
        apellidos,
        documentType,
        documento,
        email,
        celular,
        celularAlterno,
        role,
        estado,
        fechaIngreso,
        horarioId,
        puedeRegularizar,
        bajaTipo,
        activadoEn,
      ];
}
