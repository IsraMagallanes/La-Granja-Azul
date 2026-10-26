import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/app.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/users/controllers/user_providers.dart';

import '../support/fakes.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  required UserRole role,
  bool activo = true,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final users = FakeUserRepository()
    ..users['u1'] = buildUser(role: role, activo: activo);
  final auth = FakeAuthRepository()..uidByEmail['u1@granja.pe'] = 'u1';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(users),
      ],
      child: const GranjaAzulApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> login(WidgetTester tester, String email, String pass) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), pass);
  await tester.tap(find.text('Iniciar sesión'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('validaciones del formulario', (tester) async {
    await pumpApp(tester, role: UserRole.admin);
    await tester.tap(find.text('Iniciar sesión'));
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
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('mesero aterriza en su módulo', (tester) async {
    await pumpApp(tester, role: UserRole.mesero);
    await login(tester, 'u1@granja.pe', 'secreta1');
    expect(
      find.text('Toma de pedidos por mesa (próximamente).'),
      findsOneWidget,
    );
  });

  testWidgets('usuario inactivo recibe acceso denegado', (tester) async {
    await pumpApp(tester, role: UserRole.cajero, activo: false);
    await login(tester, 'u1@granja.pe', 'secreta1');
    expect(find.textContaining('desactivada'), findsOneWidget);
  });
}
