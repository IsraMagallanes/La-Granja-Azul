import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/app.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/core/error/error_mapper.dart';
import 'package:granja_azul/core/routing/app_routes.dart';
import 'package:granja_azul/core/routing/auth_redirect.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/auth/services/activation_tracker.dart';
import 'package:granja_azul/features/auth/services/session_resolver.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/roles/services/role_navigation.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/services/staff_service.dart';
import 'package:granja_azul/features/staff/services/whatsapp_invite.dart';
import 'package:granja_azul/features/users/controllers/user_providers.dart';

import '../support/fakes.dart';
import '../support/phase3_fakes.dart';

class _FakeOpener implements UrlOpener {
  Uri? opened;
  bool canOpen = true;

  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    return canOpen;
  }
}

void main() {
  group('acceso: perfil activo + correo verificado', () {
    final user = buildUser(role: UserRole.mesero);

    test('activo y verificado entra', () {
      expect(SessionResolver.fromProfile(user), isA<Authenticated>());
    });

    test('activo pero sin verificar NO entra al dashboard', () {
      final s = SessionResolver.fromProfile(user, emailVerified: false);
      expect(s, isA<EmailUnverified>());
      expect(s, isNot(isA<Authenticated>()));
    });

    test('inactivo se rechaza aunque esté verificado (y antes que "sin verificar")', () {
      final inactive = buildUser(activo: false);
      expect(SessionResolver.fromProfile(inactive), isA<AccessDenied>());
      expect(SessionResolver.fromProfile(inactive, emailVerified: false), isA<AccessDenied>());
    });

    test('sin perfil se rechaza', () {
      expect(SessionResolver.fromProfile(null), isA<AccessDenied>());
    });

    test('las terminales no necesitan correo verificado', () {
      const t = AttendanceTerminal(uid: 't', nombre: 'Tablet', activo: true);
      expect(SessionResolver.fromAccount(null, t, emailVerified: false), isA<TerminalAuthenticated>());
    });

    test('la sesión sin verificar solo puede estar en /verificar-correo', () {
      const redirect = AuthRedirect(RoleNavigation(PermissionService()));
      final session = EmailUnverified(user);
      expect(redirect.redirect(AppRoute.verifyEmail.path, session), isNull);
      expect(redirect.redirect(AppRoute.waiter.path, session), AppRoute.verifyEmail.path);
      expect(redirect.redirect(AppRoute.login.path, session), AppRoute.verifyEmail.path);
      // Ya verificado no se queda en la pantalla de verificación.
      expect(redirect.redirect(AppRoute.verifyEmail.path, Authenticated(user)), AppRoute.waiter.path);
    });
  });

  group('activación del trabajador', () {
    test('«Pendiente de activación» hasta la primera entrada verificada', () {
      expect(memberOf('m1').pendienteActivacion, isTrue);
      expect(memberOf('m1', estado: StaffStatus.baja).pendienteActivacion, isFalse);
      final activated = memberOf('m1');
      // activadoEn se llena desde Firestore.
      expect(
        memberOf('m2').pendienteActivacion,
        isTrue,
        reason: 'enviar el correo no activa la cuenta',
      );
      expect(activated.activadoEn, isNull);
    });

    test('se registra una sola vez al entrar con el correo verificado', () async {
      final users = FakeUserRepository();
      final tracker = ActivationTracker(users);
      final session = Authenticated(buildUser(uid: 'u1'));
      await tracker.onSession(session);
      await tracker.onSession(session);
      expect(users.activated, ['u1']);
    });

    test('no se registra si el correo no está verificado, está inactivo o ya estaba activada', () async {
      final users = FakeUserRepository();
      final tracker = ActivationTracker(users);
      await tracker.onSession(EmailUnverified(buildUser(uid: 'u1')));
      await tracker.onSession(const AccessDenied(AccessDeniedReason.inactive));
      await tracker.onSession(const Unauthenticated());
      await tracker.onSession(null);
      await tracker.onSession(Authenticated(buildUser(uid: 'u2').copyWithActivated(DateTime(2026))));
      expect(users.activated, isEmpty);
    });

    test('un fallo al registrar no bloquea y se reintenta después', () async {
      final users = _FailingUsers();
      final tracker = ActivationTracker(users);
      final session = Authenticated(buildUser(uid: 'u1'));
      await tracker.onSession(session);
      users.fail = false;
      await tracker.onSession(session);
      expect(users.activated, ['u1']);
    });
  });

  group('registro: fallos parciales', () {
    test('el resultado distingue qué correos de activación salieron', () async {
      final staff = FakeStaffRepository()
        ..resetEmailSent = false
        ..verificationSent = false;
      final service = StaffService(staff, FakeRestrictionRepository());
      final r = await service.create(actorOf(UserRole.admin), draftOf());
      expect(r.uid, isNotEmpty); // la cuenta y la ficha existen
      expect(r.resetEmailSent, isFalse);
      expect(r.verificationSent, isFalse);
    });

    test('correo ya registrado en Auth: mensaje claro', () {
      final e = ErrorMapper.map(_CodeError('email-already-in-use'));
      expect(e.message, contains('Ya existe una cuenta'));
    });

    test('un duplicado se detecta antes de crear cuentas', () async {
      final staff = FakeStaffRepository()..emails.add('nuevo@granja.pe');
      final service = StaffService(staff, FakeRestrictionRepository());
      await expectLater(service.create(actorOf(UserRole.admin), draftOf()), throwsA(isA<AppFailure>()));
      expect(staff.created, isEmpty);
    });
  });

  group('bienvenida por WhatsApp (wa.me)', () {
    test('arma el enlace con +51 y el celular registrado', () {
      final uri = WhatsAppInvite.uriFor(celular: '987654321', nombres: 'Ana');
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/51987654321');
      expect(uri.queryParameters['text'], startsWith('Hola Ana,'));
    });

    test('el mensaje no incluye contraseñas ni enlaces de activación', () {
      final text = WhatsAppInvite.message('Ana').toLowerCase();
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('oobcode')));
      expect(text, isNot(contains('firebaseapp')));
      expect(text, isNot(matches(RegExp(r'contraseña\s*[:=]'))));
      expect(text, contains('correo'));
    });

    test('rechaza celulares inválidos', () {
      expect(() => WhatsAppInvite.uriFor(celular: '12345', nombres: 'Ana'), throwsA(isA<AppFailure>()));
      expect(() => WhatsAppInvite.uriFor(celular: '887654321', nombres: 'Ana'), throwsA(isA<AppFailure>()));
    });

    test('abre WhatsApp mediante el abridor y no envía nada por su cuenta', () async {
      final opener = _FakeOpener();
      await WhatsAppInvite(opener).send(celular: '987654321', nombres: 'Ana');
      expect(opener.opened!.host, 'wa.me');
    });

    test('informa si no se puede abrir WhatsApp', () async {
      final opener = _FakeOpener()..canOpen = false;
      await expectLater(
        WhatsAppInvite(opener).send(celular: '987654321', nombres: 'Ana'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('flujo en la app', () {
    Future<(FakeAuthRepository, FakeUserRepository)> pump(
      WidgetTester tester, {
      bool verified = true,
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final users = FakeUserRepository()..users['u1'] = buildUser(role: UserRole.admin);
      final auth = FakeAuthRepository(initialUid: 'u1', verified: verified);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          userRepositoryProvider.overrideWithValue(users),
        ],
        child: const GranjaAzulApp(),
      ));
      await tester.pumpAndSettle();
      return (auth, users);
    }

    testWidgets('sin verificar: ve la pantalla de verificación, no el dashboard', (tester) async {
      await pump(tester, verified: false);
      expect(find.text('Verifica tu correo'), findsOneWidget);
      expect(find.textContaining('Bienvenido'), findsNothing);
    });

    testWidgets('puede reenviar la verificación y la recuperación de contraseña', (tester) async {
      final (auth, _) = await pump(tester, verified: false);
      await tester.tap(find.text('Reenviar correo de verificación'));
      await tester.pumpAndSettle();
      expect(auth.verificationsSent, 1);
      await tester.tap(find.text('Reenviar enlace de contraseña'));
      await tester.pumpAndSettle();
      expect(auth.resets, ['u1@granja.pe']);
    });

    testWidgets('al verificar entra al dashboard y se registra la activación una vez', (tester) async {
      final (auth, users) = await pump(tester, verified: false);
      expect(users.activated, isEmpty);
      await tester.tap(find.text('Ya verifiqué'));
      await tester.pumpAndSettle();
      expect(auth.reloads, 1);
      expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
      expect(users.activated, ['u1']);
    });

    testWidgets('verificado y activo entra directo, sin otro cambio de contraseña', (tester) async {
      final (auth, users) = await pump(tester);
      expect(find.text('Bienvenido, Usuario u1'), findsOneWidget);
      expect(find.text('Verifica tu correo'), findsNothing);
      expect(auth.resets, isEmpty);
      expect(users.activated, ['u1']);
    });

    testWidgets('el perfil desactivado no entra aunque el correo esté verificado', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final users = FakeUserRepository()..users['u1'] = buildUser(activo: false);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(initialUid: 'u1')),
          userRepositoryProvider.overrideWithValue(users),
        ],
        child: const GranjaAzulApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('desactivada'), findsOneWidget);
    });
  });
}

class _CodeError implements Exception {
  _CodeError(this.code);
  final String code;
}

class _FailingUsers extends FakeUserRepository {
  bool fail = true;

  @override
  Future<void> markActivated(String uid) async {
    if (fail) throw const AppFailure('sin red');
    await super.markActivated(uid);
  }
}
