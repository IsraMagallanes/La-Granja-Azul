import '../models/permission.dart';
import '../models/user_role.dart';

/// Única fuente de verdad de la matriz rol → permisos en el cliente.
/// Debe mantenerse alineada con `firestore.rules`.
class PermissionService {
  const PermissionService();

  static const _adminPermissions = {
    Permission.viewDashboard,
    Permission.manageStaff,
    Permission.manageMenu,
    Permission.viewTables,
    Permission.viewOrders,
    Permission.manageInventory,
    Permission.viewReports,
    Permission.manageAttendance,
    Permission.ownAttendance,
  };

  static final Map<UserRole, Set<Permission>> _matrix = {
    UserRole.superadmin: {
      ..._adminPermissions,
      Permission.manageAdmins,
      Permission.manageRoles,
      Permission.manageTerminals,
      Permission.manageRestrictions,
      Permission.viewAudit,
    },
    UserRole.admin: _adminPermissions,
    UserRole.mesero: {
      Permission.viewTables,
      Permission.takeOrders,
      Permission.ownAttendance,
    },
    UserRole.cocina: {
      Permission.useKitchen,
      Permission.viewOrders,
      Permission.ownAttendance,
    },
    UserRole.cajero: {
      Permission.useCashier,
      Permission.viewOrders,
      Permission.viewTables,
      Permission.ownAttendance,
    },
    UserRole.almacen: {
      Permission.manageInventory,
      Permission.ownAttendance,
    },
  };

  Set<Permission> permissionsOf(UserRole role) => _matrix[role]!;

  bool can(UserRole role, Permission permission) =>
      permissionsOf(role).contains(permission);
}
