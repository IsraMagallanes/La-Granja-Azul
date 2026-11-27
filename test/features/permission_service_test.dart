import 'dart:convert';
import 'dart:io';

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

  test('los permisos de pantalla de cada rol no cambiaron con la matriz por acción', () {
    final adminPermissions = {
      Permission.viewDashboard,
      Permission.manageStaff,
      Permission.manageMenu,
      Permission.manageTables,
      Permission.takeOrders,
      Permission.viewTables,
      Permission.viewOrders,
      Permission.viewReservations,
      Permission.manageReservations,
      Permission.useKitchen,
      Permission.useCashier,
      Permission.manageSupplies,
      Permission.viewSupplyCosts,
      Permission.managePurchasing,
      Permission.manageUtensils,
      Permission.viewUtensilCosts,
      Permission.viewReports,
      Permission.manageAttendance,
      Permission.ownAttendance,
    };
    expect(service.permissionsOf(UserRole.admin), adminPermissions);
    expect(service.permissionsOf(UserRole.superadmin), {
      ...adminPermissions,
      Permission.manageAdmins,
      Permission.manageRoles,
      Permission.manageTerminals,
      Permission.manageRestrictions,
      Permission.viewAudit,
    });
    expect(service.permissionsOf(UserRole.mesero), {
      Permission.viewTables,
      Permission.takeOrders,
      Permission.viewOrders,
      Permission.viewReservations,
      Permission.manageReservations,
      Permission.manageUtensils,
      Permission.ownAttendance,
    });
    expect(service.permissionsOf(UserRole.cocina), {
      Permission.useKitchen,
      Permission.manageSupplies,
      Permission.viewOrders,
      Permission.ownAttendance,
    });
    expect(service.permissionsOf(UserRole.cajero), {
      Permission.useCashier,
      Permission.viewOrders,
      Permission.viewTables,
      Permission.viewReservations,
      Permission.ownAttendance,
    });
  });

  group('permisos por acción', () {
    test('ver es requisito de cualquier otra acción sobre el módulo', () {
      for (final role in UserRole.values) {
        for (final module in AppModule.values) {
          final actions = service.actionsOf(role, module);
          if (actions.isNotEmpty && module != AppModule.restrictions) {
            expect(
              actions,
              contains(PermissionAction.read),
              reason: '${role.name} · ${module.name}',
            );
          }
        }
      }
    });

    test('nadie puede eliminar: el histórico se conserva (baja lógica)', () {
      for (final role in UserRole.values) {
        for (final module in AppModule.values) {
          expect(service.canDo(role, module, PermissionAction.delete), isFalse);
        }
      }
    });

    test('solo el Superadmin crea o edita terminales, restricciones y asigna admins', () {
      for (final role in UserRole.values) {
        final isSuper = role == UserRole.superadmin;
        expect(
          service.canDo(role, AppModule.terminals, PermissionAction.create),
          isSuper,
        );
        expect(
          service.canDo(role, AppModule.terminals, PermissionAction.special),
          isSuper,
        );
        expect(
          service.canDo(role, AppModule.restrictions, PermissionAction.update),
          isSuper,
        );
        expect(
          service.canDo(role, AppModule.staff, PermissionAction.special),
          isSuper,
        );
      }
    });

    test('el Admin solo consulta restricciones; no las administra', () {
      expect(
        service.canDo(
          UserRole.admin,
          AppModule.restrictions,
          PermissionAction.read,
        ),
        isTrue,
      );
      expect(
        service.can(UserRole.admin, Permission.manageRestrictions),
        isFalse,
      );
    });

    test('cocina y caja no editan la carta ni el personal', () {
      for (final role in [UserRole.cocina, UserRole.cajero]) {
        expect(service.actionsOf(role, AppModule.menu), isEmpty);
        expect(service.actionsOf(role, AppModule.staff), isEmpty);
      }
    });

    test('todos los roles generan su asistencia y ven la propia', () {
      for (final role in UserRole.values) {
        expect(
          service.canDo(role, AppModule.selfAttendance, PermissionAction.read),
          isTrue,
        );
        expect(
          service.canDo(
            role,
            AppModule.selfAttendance,
            PermissionAction.create,
          ),
          isTrue,
        );
      }
    });
  });

  group('asistencia como condición de acceso operativo', () {
    test('Superadmin y Admin están exentos; el resto no', () {
      for (final role in UserRole.values) {
        final exempt = role == UserRole.superadmin || role == UserRole.admin;
        expect(service.isShiftExempt(role), exempt, reason: role.name);
      }
    });

    test('sin jornada abierta solo los exentos conservan acceso', () {
      for (final role in UserRole.values) {
        expect(service.hasShiftAccess(role, onShift: true), isTrue);
        expect(
          service.hasShiftAccess(role, onShift: false),
          service.isShiftExempt(role),
          reason: role.name,
        );
      }
    });
  });

  // Contrato con `firestore.rules`: `tools/permissions.rules.test.js` ejecuta
  // cada celda de esta matriz contra las reglas en el emulador. Si cambias la
  // matriz, regenera el archivo con:
  //   $env:UPDATE_PERMISSION_MATRIX='1'; flutter test test/features/permission_service_test.dart
  test(
    'la matriz exportada coincide con tools/fixtures/permission_matrix.json',
    () {
      final file = File('tools/fixtures/permission_matrix.json');
      const encoder = JsonEncoder.withIndent('  ');
      final current = '${encoder.convert(service.matrixAsJson())}\n';
      if (Platform.environment['UPDATE_PERMISSION_MATRIX'] == '1') {
        file.writeAsStringSync(current);
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Falta el archivo: genéralo con UPDATE_PERMISSION_MATRIX=1.',
      );
      expect(
        file.readAsStringSync().replaceAll('\r\n', '\n'),
        current,
        reason:
            'La matriz cambió. Regenera tools/fixtures/permission_matrix.json '
            'con UPDATE_PERMISSION_MATRIX=1 y vuelve a correr '
            'tools/permissions.rules.test.js para comprobar las reglas.',
      );
    },
  );
}
