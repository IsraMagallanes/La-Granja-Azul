import '../../roles/models/user_role.dart';
import 'document_type.dart';

/// Datos de entrada del formulario de trabajador (alta o edición).
class StaffDraft {
  const StaffDraft({
    required this.nombres,
    required this.apellidos,
    required this.documentType,
    required this.documento,
    required this.email,
    required this.celular,
    required this.role,
    required this.fechaIngreso,
    this.celularAlterno,
  });

  final String nombres;
  final String apellidos;
  final DocumentType documentType;
  final String documento;
  final String email;
  final String celular;
  final String? celularAlterno;
  final UserRole role;
  final DateTime fechaIngreso;

  String get documentoNormalizado => documentType.normalize(documento);
  String get emailNormalizado => email.trim().toLowerCase();
  String? get alternoNormalizado {
    final value = celularAlterno?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
