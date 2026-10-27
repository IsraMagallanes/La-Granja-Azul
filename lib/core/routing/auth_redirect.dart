import '../config/app_config.dart';
import '../../features/auth/models/session_state.dart';
import '../../features/roles/models/user_role.dart';
import '../../features/roles/services/role_navigation.dart';
import 'app_routes.dart';

/// Lógica pura de redirección según sesión, rol y estado del usuario.
class AuthRedirect {
  const AuthRedirect(this._navigation);

  final RoleNavigation _navigation;

  static const _anonymousRoutes = {
    AppRoute.publicMenu,
    AppRoute.login,
    AppRoute.forgotPassword,
  };

  /// [session] es `null` mientras se verifica la sesión.
  String? redirect(String path, SessionState? session) {
    final route = AppRoute.fromPath(path);
    if (route == AppRoute.publicMenu) return null;

    return switch (session) {
      null => route == AppRoute.loading ? null : AppRoute.loading.path,
      Unauthenticated() => _anonymousRoutes.contains(route)
          ? null
          : (AppConfig.publicEntryIsMenu ? AppRoute.publicMenu : AppRoute.login)
              .path,
      AccessDenied() =>
        route == AppRoute.accessDenied ? null : AppRoute.accessDenied.path,
      EmailUnverified() =>
        route == AppRoute.verifyEmail ? null : AppRoute.verifyEmail.path,
      TerminalAuthenticated() => route == AppRoute.attendanceTerminal
          ? null
          : AppRoute.attendanceTerminal.path,
      Authenticated(:final user) => _forUser(route, user.role),
    };
  }

  String? _forUser(AppRoute? route, UserRole role) {
    final home = _navigation.homeFor(role).path;
    if (route == null || !route.isStaff) return home;
    return _navigation.canAccess(role, route) ? null : home;
  }
}
