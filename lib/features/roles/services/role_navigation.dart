import '../../../core/routing/app_routes.dart';
import '../models/user_role.dart';
import 'permission_service.dart';

/// Resuelve qué rutas de personal puede ver cada rol. [onShift] indica si el
/// trabajador tiene la jornada abierta; los módulos operativos lo exigen salvo
/// a los roles exentos (Superadmin y Admin).
class RoleNavigation {
  const RoleNavigation(this._permissions);

  final PermissionService _permissions;

  List<AppRoute> routesFor(UserRole role, {bool onShift = true}) => [
    for (final route in AppRoute.values)
      if (route.isStaff && canAccess(role, route, onShift: onShift)) route,
  ];

  bool canAccess(UserRole role, AppRoute route, {bool onShift = true}) {
    if (route.permission != null &&
        !_permissions.can(role, route.permission!)) {
      return false;
    }
    return !route.requiresShift ||
        _permissions.hasShiftAccess(role, onShift: onShift);
  }

  AppRoute homeFor(UserRole role, {bool onShift = true}) =>
      routesFor(role, onShift: onShift).first;
}
