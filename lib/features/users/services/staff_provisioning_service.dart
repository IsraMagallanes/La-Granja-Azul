import '../../roles/models/user_role.dart';

/// Datos para dar de alta a un miembro del personal.
class NewStaffMember {
  const NewStaffMember({
    required this.email,
    required this.nombre,
    required this.role,
  });

  final String email;
  final String nombre;
  final UserRole role;
}

/// Contrato para crear administradores y trabajadores.
///
/// Crear cuentas de Firebase Auth exige privilegios de servidor (Admin SDK),
/// por lo que jamás se implementa con el SDK de cliente. La implementación
/// futura invocará una operación de servidor (p. ej. Cloud Functions, que
/// requiere el plan Blaze) que verifique que quien llama es superadmin.
abstract interface class StaffProvisioningService {
  /// Crea la cuenta y su documento `usuarios/{uid}`; devuelve el UID.
  Future<String> createStaff(NewStaffMember member);

  Future<void> setActive(String uid, {required bool active});
}
