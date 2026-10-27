import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/app.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/users/controllers/user_providers.dart';

import '../support/fakes.dart';

Future<FakeAuthRepository> pumpApp(
  WidgetTester tester, {
  String? initialUid,
  UserRole role = UserRole.superadmin,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final users = FakeUserRepository()..users['u1'] = buildUser(role: role);
  final auth = FakeAuthRepository(initialUid: initialUid);
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
  return auth;
}

void main() {
  testWidgets('sesión persistida: entra directo al dashboard del superadmin',
      (tester) async {
    await pumpApp(tester, initialUid: 'u1');
    expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
    expect(find.text('Roles y permisos'), findsWidgets);
  });

  testWidgets('recuperación de contraseña envía el correo y confirma',
      (tester) async {
    final auth = await pumpApp(tester);
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'u1@granja.pe');
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    expect(auth.resets, ['u1@granja.pe']);
    expect(find.textContaining('Firebase aceptó la solicitud'), findsOneWidget);
  });

  testWidgets('recuperación valida el correo', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar enlace'));
    await tester.pump();
    expect(find.text('El correo es obligatorio.'), findsOneWidget);
  });
}
