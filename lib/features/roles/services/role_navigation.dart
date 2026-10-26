import '../../../core/routing/app_routes.dart';
import '../models/user_role.dart';
import 'permission_service.dart';

/// Resuelve qué rutas de personal puede ver cada rol.
class RoleNavigation {
  const RoleNavigation(this._permissions);

  final PermissionService _permissions;

  List<AppRoute> routesFor(UserRole role) => [
        for (final route in AppRoute.values)
          if (route.isStaff && _permissions.can(role, route.permission!)) route,
      ];

  bool canAccess(UserRole role, AppRoute route) =>
      route.permission == null || _permissions.can(role, route.permission!);

  AppRoute homeFor(UserRole role) => routesFor(role).first;
}
