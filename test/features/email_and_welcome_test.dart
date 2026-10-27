import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/async/request_guard.dart';
import 'package:granja_azul/core/error/error_mapper.dart';
import 'package:granja_azul/core/widgets/progress_dialog.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/services/email_requester.dart';
import 'package:granja_azul/features/staff/controllers/staff_providers.dart';
import 'package:granja_azul/features/staff/services/staff_service.dart';
import 'package:granja_azul/features/staff/services/whatsapp_invite.dart';
import 'package:granja_azul/features/staff/widgets/created_staff_dialog.dart';

import '../support/fakes.dart';
import '../support/phase3_fakes.dart';

/// Auth que puede tardar, fallar o responder, para probar el envío de correos.
class _ControlledAuth extends FakeAuthRepository {
  _ControlledAuth() : super(initialUid: 'u1');

  Completer<void>? gate;
  Object? error;
  int calls = 0;

  @override
  Future<void> sendPasswordReset(String email) async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    await super.sendPasswordReset(email);
  }
}

class _Opener implements UrlOpener {
  Uri? opened;
  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    return true;
  }
}

void main() {
  group('RequestGuard', () {
    test('tras un éxito pide esperar antes de repetir', () async {
      var now = DateTime(2026, 1, 1);
      final guard = RequestGuard(cooldown: const Duration(seconds: 60), now: () => now);
      expect(await guard.run('k', () async {}), isA<GuardDone>());
      final blocked = await guard.run('k', () async {});
      expect(blocked, isA<GuardCoolingDown>());
      now = now.add(const Duration(seconds: 61));
      expect(await guard.run('k', () async {}), isA<GuardDone>());
    });

    test('no duplica una solicitud en curso con la misma clave', () async {
      final guard = RequestGuard();
      final gate = Completer<void>();
      final first = guard.run('k', () => gate.future);
      expect(guard.isRunning('k'), isTrue);
      expect(await guard.run('k', () async {}), isA<GuardBusy>());
      gate.complete();
      expect(await first, isA<GuardDone>());
      expect(guard.isRunning('k'), isFalse);
    });

    test('un tiempo agotado no se da por enviado y permite reintentar de inmediato', () async {
      final guard = RequestGuard(timeout: const Duration(milliseconds: 20));
      final out = await guard.run('k', () => Completer<void>().future);
      expect(out, isA<GuardFailed>());
      expect((out as GuardFailed).timedOut, isTrue);
      expect(await guard.run('k', () async {}), isA<GuardDone>());
    });

    test('un error se traduce a un mensaje claro y no activa la pausa', () async {
      final guard = RequestGuard();
      final out = await guard.run('k', () async => throw TimeoutException('x'));
      expect((out as GuardFailed).failure.code, 'timeout');
      expect(ErrorMapper.map(TimeoutException('x')).code, 'timeout');
      expect(await guard.run('k', () async {}), isA<GuardDone>());
    });
  });

  group('EmailRequester', () {
    test('éxito: dice que Firebase aceptó la solicitud, no que se entregó', () async {
      final auth = _ControlledAuth();
      final r = await EmailRequester(auth, RequestGuard()).sendPasswordReset(' U1@Granja.pe ');
      expect(r.ok, isTrue);
      expect(r.message, contains('aceptó'));
      expect(auth.resets, ['u1@granja.pe']);
    });

    test('fallo: no afirma que se envió y permite reintentar sin pausa', () async {
      final auth = _ControlledAuth()..error = _CodeError('network-request-failed');
      final requester = EmailRequester(auth, RequestGuard());
      final failed = await requester.sendPasswordReset('u1@granja.pe');
      expect(failed.ok, isFalse);
      expect(failed.message, isNot(contains('aceptó')));
      expect(failed.message, contains('Sin conexión'));

      auth.error = null;
      final retry = await requester.sendPasswordReset('u1@granja.pe');
      expect(retry.ok, isTrue);
      expect(auth.calls, 2);
    });

    test('tiempo agotado: informa que no se confirmó', () async {
      final auth = _ControlledAuth()..gate = Completer<void>();
      final r = await EmailRequester(auth, RequestGuard(timeout: const Duration(milliseconds: 20)))
          .sendPasswordReset('u1@granja.pe');
      expect(r.ok, isFalse);
      expect(r.message, contains('No se pudo confirmar'));
      expect(auth.resets, isEmpty);
    });

    test('toques repetidos no envían dos solicitudes', () async {
      final auth = _ControlledAuth()..gate = Completer<void>();
      final requester = EmailRequester(auth, RequestGuard());
      final first = requester.sendPasswordReset('u1@granja.pe');
      final second = await requester.sendPasswordReset('u1@granja.pe');
      expect(second.ok, isFalse);
      expect(second.message, contains('en curso'));
      auth.gate!.complete();
      expect((await first).ok, isTrue);
      expect(auth.calls, 1);

      final third = await requester.sendPasswordReset('u1@granja.pe');
      expect(third.message, contains('Podrás reintentar'));
      expect(auth.calls, 1);
    });

    test('verificación usa su propio mensaje', () async {
      final auth = _ControlledAuth();
      final r = await EmailRequester(auth, RequestGuard()).sendVerification();
      expect(r.ok, isTrue);
      expect(auth.verificationsSent, 1);
    });
  });

  group('diálogo de alta exitosa', () {
    Future<(_ControlledAuth, _Opener)> open(
      WidgetTester tester, {
      bool resetOk = true,
      bool verificationOk = true,
    }) async {
      final auth = _ControlledAuth();
      final opener = _Opener();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          urlOpenerProvider.overrideWithValue(opener),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CreatedStaffDialog(
                  draft: draftOf(celular: '987654321', email: 'nuevo@granja.pe'),
                  result: CreateStaffResult('uid-1',
                      resetEmailSent: resetOk, verificationSent: verificationOk),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return (auth, opener);
    }

    testWidgets('muestra «Enviar bienvenida por WhatsApp» y «Finalizar»', (tester) async {
      await open(tester);
      expect(find.text('Enviar bienvenida por WhatsApp'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);
      expect(find.textContaining('Pendiente de activación'), findsOneWidget);
    });

    testWidgets('WhatsApp abre wa.me con +51, mensaje preparado y sin datos privados', (tester) async {
      final (_, opener) = await open(tester);
      await tester.tap(find.text('Enviar bienvenida por WhatsApp'));
      await tester.pumpAndSettle();
      final uri = opener.opened!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/51987654321');
      final text = uri.queryParameters['text']!.toLowerCase();
      expect(text, isNot(contains('contraseña:')));
      expect(text, isNot(contains('http')));
      // El diálogo sigue abierto: el envío es manual y se finaliza aparte.
      expect(find.text('Finalizar'), findsOneWidget);
    });

    testWidgets('no se cierra al tocar fuera; «Finalizar» lo cierra', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byType(CreatedStaffDialog), findsOneWidget);
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();
      expect(find.byType(CreatedStaffDialog), findsNothing);
    });

    testWidgets('si el correo de contraseña no se confirmó, no dice que se envió y permite reintentar', (tester) async {
      final (auth, _) = await open(tester, resetOk: false);
      expect(find.textContaining('No se confirmó el envío del correo para crear contraseña'), findsOneWidget);
      expect(find.textContaining('Firebase aceptó el envío.'), findsOneWidget); // solo la verificación

      await tester.tap(find.text('Reintentar envío'));
      await tester.pumpAndSettle();
      expect(auth.resets, ['nuevo@granja.pe']);
      expect(find.textContaining('Correo para crear contraseña: Firebase aceptó el envío.'), findsOneWidget);
    });
  });

  testWidgets('runWithProgress muestra el progreso y lo cierra al terminar', (tester) async {
    final gate = Completer<int>();
    int? value;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => value = await runWithProgress(context,
              message: 'Trabajando…', task: () => gate.future),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Trabajando…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete(7);
    await tester.pumpAndSettle();
    expect(find.text('Trabajando…'), findsNothing);
    expect(value, 7);
  });

  testWidgets('runWithProgress cierra el progreso si la tarea falla', (tester) async {
    Object? caught;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            try {
              await runWithProgress<void>(context,
                  message: 'Trabajando…', task: () async => throw StateError('x'));
            } catch (e) {
              caught = e;
            }
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Trabajando…'), findsNothing);
    expect(caught, isA<StateError>());
  });
}

class _CodeError implements Exception {
  _CodeError(this.code);
  final String code;
}
