enum UserRole {
  superadmin('superadmin', 'Superadministrador'),
  admin('admin', 'Administrador'),
  mesero('mesero', 'Mesero'),
  cocina('cocina', 'Cocina'),
  cajero('cajero', 'Cajero'),
  almacen('almacen', 'Almacén');

  const UserRole(this.value, this.label);

  /// Valor almacenado en Firestore (`usuarios/{uid}.rol`).
  final String value;
  final String label;

  static UserRole? tryParse(Object? raw) {
    for (final role in values) {
      if (role.value == raw) return role;
    }
    return null;
  }
}
