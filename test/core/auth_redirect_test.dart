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

  SessionState session(UserRole role) => Authenticated(buildUser(role: role));

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

  group('asistencia como condición de acceso operativo', () {
    SessionState shift(UserRole role, {required bool open}) =>
        Authenticated(buildUser(role: role), onShift: open);

    const operational = [
      AppRoute.waiter,
      AppRoute.kitchen,
      AppRoute.cashier,
      AppRoute.inventory,
      AppRoute.tables,
      AppRoute.orders,
    ];

    test('sin entrada, cada rol operativo cae en «Mi asistencia»', () {
      for (final role in [
        UserRole.mesero,
        UserRole.cocina,
        UserRole.cajero,
        UserRole.almacen,
      ]) {
        final s = shift(role, open: false);
        expect(
          redirect.redirect(AppRoute.login.path, s),
          AppRoute.myAttendance.path,
          reason: role.name,
        );
        for (final route in operational) {
          expect(
            redirect.redirect(route.path, s),
            AppRoute.myAttendance.path,
            reason: '${role.name} ${route.path}',
          );
        }
        // «Mi asistencia» siempre disponible para poder registrar la entrada.
        expect(
          redirect.redirect(AppRoute.myAttendance.path, s),
          isNull,
          reason: role.name,
        );
      }
    });

    test('con la entrada registrada recuperan su pantalla de siempre', () {
      expect(
        redirect.redirect(
          AppRoute.myAttendance.path,
          shift(UserRole.mesero, open: true),
        ),
        isNull,
      );
      expect(
        redirect.redirect(
          AppRoute.login.path,
          shift(UserRole.mesero, open: true),
        ),
        AppRoute.waiter.path,
      );
      expect(
        redirect.redirect(
          AppRoute.kitchen.path,
          shift(UserRole.cocina, open: true),
        ),
        isNull,
      );
    });

    test(
      'al registrar la salida pierden el acceso a la ruta que tenían abierta',
      () {
        expect(
          redirect.redirect(
            AppRoute.waiter.path,
            shift(UserRole.mesero, open: true),
          ),
          isNull,
        );
        expect(
          redirect.redirect(
            AppRoute.waiter.path,
            shift(UserRole.mesero, open: false),
          ),
          AppRoute.myAttendance.path,
        );
      },
    );

    test('Superadmin y Admin están exentos aunque no haya jornada abierta', () {
      for (final role in [UserRole.superadmin, UserRole.admin]) {
        final s = shift(role, open: false);
        expect(
          redirect.redirect(AppRoute.login.path, s),
          AppRoute.dashboard.path,
        );
        expect(redirect.redirect(AppRoute.tables.path, s), isNull);
        expect(redirect.redirect(AppRoute.orders.path, s), isNull);
        expect(redirect.redirect(AppRoute.waiter.path, s), isNull);
      }
    });

    test('la jornada no sustituye al permiso del rol', () {
      expect(
        redirect.redirect(
          AppRoute.kitchen.path,
          shift(UserRole.mesero, open: true),
        ),
        AppRoute.waiter.path,
      );
      expect(
        redirect.redirect(
          AppRoute.users.path,
          shift(UserRole.almacen, open: true),
        ),
        AppRoute.inventory.path,
      );
    });

    test('rutas no operativas del rol no exigen jornada', () {
      final s = shift(UserRole.superadmin, open: false);
      expect(redirect.redirect(AppRoute.terminals.path, s), isNull);
      expect(redirect.redirect(AppRoute.audit.path, s), isNull);
    });
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
    expect(
      redirect.redirect(AppRoute.roles.path, session(UserRole.superadmin)),
      isNull,
    );
  });
}
