import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';

void main() {
  const service = PermissionService();

  test('solo el superadmin gestiona administradores y roles', () {
    for (final role in UserRole.values) {
      final isSuper = role == UserRole.superadmin;
      expect(service.can(role, Permission.manageAdmins), isSuper);
      expect(service.can(role, Permission.manageRoles), isSuper);
    }
  });

  test('admin comparte dashboard con superadmin', () {
    expect(service.can(UserRole.admin, Permission.viewDashboard), isTrue);
    expect(service.can(UserRole.mesero, Permission.viewDashboard), isFalse);
  });

  test('todos los roles tienen al menos un permiso', () {
    for (final role in UserRole.values) {
      expect(service.permissionsOf(role), isNotEmpty);
    }
  });
}
