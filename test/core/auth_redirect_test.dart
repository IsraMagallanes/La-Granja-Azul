import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/routing/app_routes.dart';
import 'package:granja_azul/core/routing/auth_redirect.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/roles/services/role_navigation.dart';

import '../support/fakes.dart';

void main() {
  const redirect = AuthRedirect(RoleNavigation(PermissionService()));

  SessionState session(UserRole role) =>
      Authenticated(buildUser(role: role));

  test('mientras carga solo se permite la carta y la pantalla de carga', () {
    expect(redirect.redirect('/app/dashboard', null), AppRoute.loading.path);
    expect(redirect.redirect(AppRoute.loading.path, null), isNull);
    expect(redirect.redirect(AppRoute.publicMenu.path, null), isNull);
  });

  test('anónimo no entra a rutas de personal', () {
    const s = Unauthenticated();
    expect(redirect.redirect('/app/dashboard', s), isNotNull);
    expect(redirect.redirect(AppRoute.login.path, s), isNull);
    expect(redirect.redirect(AppRoute.publicMenu.path, s), isNull);
  });

  test('usuario inactivo o sin perfil va a acceso denegado', () {
    const s = AccessDenied(AccessDeniedReason.inactive);
    expect(redirect.redirect('/app/dashboard', s), AppRoute.accessDenied.path);
    expect(redirect.redirect(AppRoute.accessDenied.path, s), isNull);
  });

  test('cada rol aterriza en su pantalla', () {
    final homes = {
      UserRole.superadmin: AppRoute.dashboard,
      UserRole.admin: AppRoute.dashboard,
      UserRole.mesero: AppRoute.waiter,
      UserRole.cocina: AppRoute.kitchen,
      UserRole.cajero: AppRoute.cashier,
      UserRole.almacen: AppRoute.inventory,
    };
    for (final e in homes.entries) {
      expect(
        redirect.redirect(AppRoute.login.path, session(e.key)),
        e.value.path,
        reason: e.key.name,
      );
    }
  });

  test('un rol no accede a rutas sin permiso', () {
    expect(
      redirect.redirect(AppRoute.users.path, session(UserRole.mesero)),
      AppRoute.waiter.path,
    );
    expect(
      redirect.redirect(AppRoute.roles.path, session(UserRole.admin)),
      AppRoute.dashboard.path,
    );
    expect(redirect.redirect(AppRoute.roles.path, session(UserRole.superadmin)),
        isNull);
  });
}
