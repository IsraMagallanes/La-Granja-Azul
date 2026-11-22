import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/app.dart';
import 'package:granja_azul/features/attendance/controllers/attendance_providers.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/users/controllers/user_providers.dart';

import '../support/fakes.dart';
import '../support/order_fakes.dart';
import '../support/phase3_fakes.dart';

import 'package:granja_azul/features/tables/controllers/table_providers.dart';
import 'package:granja_azul/features/orders/controllers/order_providers.dart';

/// Repositorio de asistencia de la última `pumpApp` (para registrar entradas y
/// salidas durante la prueba).
late FakeWorkerAttendanceRepository attendance;

Future<void> pumpApp(
  WidgetTester tester, {
  required UserRole role,
  bool activo = true,
  bool onShift = true,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final users = FakeUserRepository()
    ..users['u1'] = buildUser(role: role, activo: activo);
  final auth = FakeAuthRepository()..uidByEmail['u1@granja.pe'] = 'u1';
  attendance = FakeWorkerAttendanceRepository();
  if (onShift) attendance.setShift('u1', open: true);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tableRepositoryProvider.overrideWithValue(FakeTableRepository()),
        orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(users),
        workerAttendanceRepositoryProvider.overrideWithValue(attendance),
      ],
      child: const GranjaAzulApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> login(WidgetTester tester, String email, String pass) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), pass);
  await tester.tap(find.text('Ingresar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('validaciones del formulario', (tester) async {
    await pumpApp(tester, role: UserRole.admin);
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('El correo es obligatorio.'), findsOneWidget);
  });

  testWidgets('credenciales inválidas muestran error', (tester) async {
    await pumpApp(tester, role: UserRole.admin);
    await login(tester, 'u1@granja.pe', 'incorrecta');
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  testWidgets('admin llega al dashboard y puede cerrar sesión', (tester) async {
    await pumpApp(tester, role: UserRole.admin);
    await login(tester, 'u1@granja.pe', 'secreta1');
    expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
    expect(find.text('Roles y permisos'), findsNothing);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.text('Ingresar'), findsOneWidget);
  });

  for (final (name, size, rail, extended) in [
    ('celular', const Size(390, 800), false, false),
    ('tablet', const Size(800, 900), true, false),
    ('escritorio', const Size(1280, 900), true, true),
  ]) {
    testWidgets('navegación en $name sin desbordes', (tester) async {
      await pumpApp(tester, role: UserRole.superadmin, size: size);
      await login(tester, 'u1@granja.pe', 'secreta1');
      expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sidebar-expanded')),
        rail && extended ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sidebar-compact')),
        rail && !extended ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mesero aterriza en su módulo', (tester) async {
    await pumpApp(tester, role: UserRole.mesero);
    await login(tester, 'u1@granja.pe', 'secreta1');
    expect(find.text('Mis pedidos'), findsOneWidget);
  });

  group('asistencia como condición de acceso operativo', () {
    testWidgets('mesero sin entrada solo ve «Mi asistencia»', (tester) async {
      await pumpApp(tester, role: UserRole.mesero, onShift: false);
      await login(tester, 'u1@granja.pe', 'secreta1');
      expect(find.text('Mis pedidos'), findsNothing);
      expect(find.text('Mi asistencia'), findsWidgets);
      expect(find.textContaining('Registra tu entrada'), findsOneWidget);
      // El menú lateral no ofrece módulos operativos.
      expect(find.text('Mesas'), findsNothing);
      expect(find.text('Pedidos'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'al registrar la entrada gana acceso y al registrar la salida lo pierde en vivo',
      (tester) async {
        await pumpApp(tester, role: UserRole.mesero, onShift: false);
        await login(tester, 'u1@granja.pe', 'secreta1');
        expect(find.text('Mis pedidos'), findsNothing);

        attendance.setShift(
          'u1',
          open: true,
        ); // la terminal registra la entrada
        await tester.pumpAndSettle();
        // Sigue en «Mi asistencia»; ya puede entrar a sus módulos.
        expect(find.text('Mesas'), findsWidgets);
        expect(find.text('Pedidos'), findsWidgets);

        attendance.setShift('u1', open: false); // registra la salida
        await tester.pumpAndSettle();
        expect(find.text('Mesas'), findsNothing);
        expect(find.text('Pedidos'), findsNothing);
        expect(find.text('Mi asistencia'), findsWidgets);
      },
    );

    testWidgets(
      'con la jornada abierta que se cierra, el mesero sale de su módulo',
      (tester) async {
        await pumpApp(tester, role: UserRole.mesero);
        await login(tester, 'u1@granja.pe', 'secreta1');
        expect(find.text('Mis pedidos'), findsOneWidget);

        attendance.setShift('u1', open: false);
        await tester.pumpAndSettle();
        expect(find.text('Mis pedidos'), findsNothing);
        expect(find.text('Mesas'), findsNothing);
      },
    );

    for (final role in [UserRole.admin, UserRole.superadmin]) {
      testWidgets('${role.label} accede sin registrar entrada', (tester) async {
        await pumpApp(tester, role: role, onShift: false);
        await login(tester, 'u1@granja.pe', 'secreta1');
        expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
        expect(find.text('Mesas'), findsWidgets);
        expect(find.text('Pedidos'), findsWidgets);
      });
    }
  });

  testWidgets('usuario inactivo recibe acceso denegado', (tester) async {
    await pumpApp(tester, role: UserRole.cajero, activo: false);
    await login(tester, 'u1@granja.pe', 'secreta1');
    expect(find.textContaining('desactivada'), findsOneWidget);
  });
}
