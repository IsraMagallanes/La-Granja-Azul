import 'package:equatable/equatable.dart';

import '../../roles/models/user_role.dart';

/// Perfil de sesión de un usuario del personal (documento `usuarios/{uid}`).
/// Solo lleva lo necesario para autenticar y autorizar; los datos personales
/// completos viven en `StaffMember`.
class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.role,
    required this.activo,
    this.nombres = '',
    this.horarioId,
    this.puedeRegularizar = false,
    this.activadoEn,
  });

  final String uid;
  final String email;
  final String nombre;
  final UserRole role;
  final bool activo;

  /// Nombres de pila (se muestran en la terminal; no el apellido ni el documento).
  final String nombres;

  /// Horario asignado (`horarios/{id}`), si tiene.
  final String? horarioId;

  /// Administrador autorizado por el Superadmin a regularizar marcaciones.
  final bool puedeRegularizar;

  /// Primera vez que entró con el correo verificado (`null` = pendiente).
  final DateTime? activadoEn;

  /// Devuelve `null` si el documento no tiene un rol válido.
  static AppUser? fromMap(String uid, Map<String, dynamic> data) {
    final role = UserRole.tryParse(data['rol']);
    if (role == null) return null;
    return AppUser(
      uid: uid,
      email: (data['email'] as String?) ?? '',
      nombre: (data['nombre'] as String?) ?? '',
      role: role,
      activo: data['activo'] == true,
      nombres: (data['nombres'] as String?) ?? '',
      horarioId: data['horarioId'] as String?,
      puedeRegularizar: data['puedeRegularizar'] == true,
      activadoEn: toDateOrNull(data['activadoEn']),
    );
  }

  AppUser copyWithActivated(DateTime when) => AppUser(
        uid: uid,
        email: email,
        nombre: nombre,
        role: role,
        activo: activo,
        nombres: nombres,
        horarioId: horarioId,
        puedeRegularizar: puedeRegularizar,
        activadoEn: when,
      );

  @override
  List<Object?> get props =>
      [uid, email, nombre, role, activo, nombres, horarioId, puedeRegularizar, activadoEn];
}

/// Convierte `DateTime` o `Timestamp` de Firestore (duck-typing: los modelos no
/// dependen de Firebase). Devuelve `null` si no hay fecha.
DateTime? toDateOrNull(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw == null) return null;
  try {
    final date = (raw as dynamic).toDate();
    return date is DateTime ? date : null;
  } on NoSuchMethodError {
    return null;
  }
}
