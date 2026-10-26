import 'package:equatable/equatable.dart';

import '../../roles/models/user_role.dart';

/// Perfil de un usuario del personal (documento `usuarios/{uid}`).
class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.role,
    required this.activo,
  });

  final String uid;
  final String email;
  final String nombre;
  final UserRole role;
  final bool activo;

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
    );
  }

  @override
  List<Object?> get props => [uid, email, nombre, role, activo];
}
