import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/attendance/controllers/terminal_providers.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/attendance/screens/terminals_screen.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/repositories/staff_repository.dart';
import 'package:granja_azul/features/attendance/controllers/attendance_providers.dart';

import '../support/phase3_fakes.dart';

void main() {
  late FakeTerminalRepository repo;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = FakeTerminalRepository()
      ..terminals['a'] = const AttendanceTerminal(
        uid: 'a',
        nombre: 'La Granja Azul',
        activo: true,
      )
      ..terminals['b'] = const AttendanceTerminal(
        uid: 'b',
        nombre: 'Asistencia',
        activo: true,
      )
      ..linked.addAll(['a', 'b']);
    // Igual que la app real: la pantalla vive dentro de un ShellRoute (navegador
    // anidado), que es donde se reproducía el bloqueo.
    final router = GoRouter(
      initialLocation: '/x',
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/x', builder: (_, _) => const TerminalsScreen()),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(
            (ref) => Stream.value(Authenticated(actorOf(UserRole.superadmin))),
          ),
          terminalRepositoryProvider.overrideWithValue(repo),
          staffAccountCreatorProvider.overrideWithValue(_NoAccounts()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(
    WidgetTester tester,
    String terminal,
    String option,
  ) async {
    await tester.tap(find.byTooltip('Opciones de $terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  group('restablecer enlace', () {
    testWidgets(
      'confirma, restablece solo ese terminal y la pantalla sigue usable',
      (tester) async {
        await pump(tester);
        await choose(tester, 'Asistencia', 'Restablecer enlace');

        // La confirmación nombra el terminal.
        expect(find.textContaining('"Asistencia"'), findsWidgets);
        await tester.tap(inDialog('Restablecer'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.resets, ['b']);
        expect(repo.linked, {'a'});
        expect(
          find.textContaining('Enlace de "Asistencia" restablecido'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Botones disponibles otra vez y Autorizar terminal responde.
        await tester.tap(find.text('Autorizar terminal'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        await choose(tester, 'La Granja Azul', 'Restablecer enlace');
        await tester.tap(inDialog('Restablecer'));
        await tester.pumpAndSettle();
        expect(repo.resets, ['b', 'a']);
      },
    );

    testWidgets('cancelar cierra el diálogo sin cambios', (tester) async {
      await pump(tester);
      await choose(tester, 'Asistencia', 'Restablecer enlace');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.resets, isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Opciones de Asistencia'), findsOneWidget);
    });

    testWidgets('muestra progreso solo en ese terminal y evita duplicados', (
      tester,
    ) async {
      await pump(tester);
      repo.gate = Completer<void>();
      await choose(tester, 'Asistencia', 'Restablecer enlace');
      await tester.tap(inDialog('Restablecer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Sin menú en el terminal ocupado; el otro sigue disponible.
      expect(find.byTooltip('Opciones de Asistencia'), findsNothing);
      expect(find.byTooltip('Opciones de La Granja Azul'), findsOneWidget);
      expect(find.text('Autorizar terminal'), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.resets, ['b']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Opciones de Asistencia'), findsOneWidget);
    });

    testWidgets('un error se informa y permite reintentar', (tester) async {
      await pump(tester);
      repo.failWith = const AppFailure('Sin permiso para esta operación.');
      await choose(tester, 'Asistencia', 'Restablecer enlace');
      await tester.tap(inDialog('Restablecer'));
      await tester.pumpAndSettle();

      expect(find.text('Sin permiso para esta operación.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repo.resets, isEmpty);

      repo.failWith = null;
      await choose(tester, 'Asistencia', 'Restablecer enlace');
      await tester.tap(inDialog('Restablecer'));
      await tester.pumpAndSettle();
      expect(repo.resets, ['b']);
    });

    testWidgets('una operación que no responde termina con un mensaje', (
      tester,
    ) async {
      await pump(tester);
      repo.gate = Completer<void>();
      await choose(tester, 'Asistencia', 'Restablecer enlace');
      await tester.tap(inDialog('Restablecer'));
      await tester.pump();
      await tester.pump(
        TerminalsScreen.operationTimeout + const Duration(seconds: 1),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('No se recibió respuesta a tiempo'),
        findsOneWidget,
      );
      expect(find.byTooltip('Opciones de Asistencia'), findsOneWidget);
      repo.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('inhabilitar, reactivar y eliminar', () {
    testWidgets(
      'inhabilitar afecta solo al seleccionado e invalida su enlace',
      (tester) async {
        await pump(tester);
        await choose(tester, 'Asistencia', 'Inhabilitar terminal');
        expect(find.textContaining('"Asistencia"'), findsWidgets);
        await tester.tap(inDialog('Inhabilitar'));
        await tester.pumpAndSettle();

        expect(repo.terminals['b']!.activo, isFalse);
        expect(repo.terminals['a']!.activo, isTrue);
        expect(repo.linked, {'a'});
        expect(find.text('Inhabilitada'), findsOneWidget);
        expect(find.text('Autorizada'), findsOneWidget);
      },
    );

    testWidgets('reactivar no recupera el enlace anterior', (tester) async {
      await pump(tester);
      await choose(tester, 'Asistencia', 'Inhabilitar terminal');
      await tester.tap(inDialog('Inhabilitar'));
      await tester.pumpAndSettle();

      await choose(tester, 'Asistencia', 'Reactivar terminal');
      await tester.tap(inDialog('Reactivar'));
      await tester.pumpAndSettle();

      expect(repo.terminals['b']!.activo, isTrue);
      expect(repo.linked, {'a'});
      expect(find.text('Inhabilitada'), findsNothing);
    });

    testWidgets('eliminar solo se ofrece a terminales inhabilitadas', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Opciones de Asistencia'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar terminal'), findsNothing);
      expect(find.text('Restablecer enlace'), findsOneWidget);
    });

    testWidgets(
      'solicitar la eliminación solo registra la solicitud: no borra nada',
      (tester) async {
        await pump(tester);
        await choose(tester, 'Asistencia', 'Inhabilitar terminal');
        await tester.tap(inDialog('Inhabilitar'));
        await tester.pumpAndSettle();

        await choose(tester, 'Asistencia', 'Solicitar eliminación definitiva');
        expect(find.textContaining('La app no elimina nada'), findsOneWidget);
        await tester.tap(inDialog('Solicitar'));
        await tester.pumpAndSettle();

        expect(repo.deletionRequests, {'b'});
        expect(repo.terminals.keys, unorderedEquals(['a', 'b']));
        expect(
          find.text('Inhabilitada · eliminación solicitada'),
          findsOneWidget,
        );
        // El mensaje aclara que aún no se eliminó.
        expect(find.textContaining('Aún no se ha eliminado'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'con la solicitud hecha se explica cómo completarla con el script',
      (tester) async {
        await pump(tester);
        await choose(tester, 'Asistencia', 'Inhabilitar terminal');
        await tester.tap(inDialog('Inhabilitar'));
        await tester.pumpAndSettle();
        await choose(tester, 'Asistencia', 'Solicitar eliminación definitiva');
        await tester.tap(inDialog('Solicitar'));
        await tester.pumpAndSettle();

        await choose(tester, 'Asistencia', 'Ver cómo completar la eliminación');
        expect(
          find.textContaining('NO se elimina desde la app'),
          findsOneWidget,
        );
        expect(find.text('b'), findsOneWidget); // UID
        expect(
          find.text('node delete_terminal.js --pendientes'),
          findsOneWidget,
        );
        expect(find.text('node delete_terminal.js b'), findsOneWidget);
        expect(find.textContaining('--execute'), findsOneWidget);
        expect(
          find.textContaining('Se conservan las asistencias'),
          findsOneWidget,
        );
        // Sin botón que afirme una eliminación.
        expect(find.text('Eliminar'), findsNothing);

        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.terminals.keys, unorderedEquals(['a', 'b']));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reactivar la terminal cancela la solicitud de eliminación', (
      tester,
    ) async {
      await pump(tester);
      await choose(tester, 'Asistencia', 'Inhabilitar terminal');
      await tester.tap(inDialog('Inhabilitar'));
      await tester.pumpAndSettle();
      await choose(tester, 'Asistencia', 'Solicitar eliminación definitiva');
      await tester.tap(inDialog('Solicitar'));
      await tester.pumpAndSettle();

      await choose(tester, 'Asistencia', 'Reactivar terminal');
      await tester.tap(inDialog('Reactivar'));
      await tester.pumpAndSettle();
      expect(repo.deletionRequests, isEmpty);
      expect(find.textContaining('eliminación solicitada'), findsNothing);
    });

    testWidgets(
      'la terminal desaparece sola cuando el documento se elimina fuera de la app',
      (tester) async {
        await pump(tester);
        repo.terminals.remove('b'); // lo que hace el script
        repo.notify();
        await tester.pumpAndSettle();
        expect(find.text('Asistencia'), findsNothing);
        expect(find.text('La Granja Azul'), findsOneWidget);
      },
    );
  });

  group('distribución', () {
    for (final size in const [
      Size(800, 220),
      Size(320, 480),
      Size(1400, 900),
    ]) {
      testWidgets(
        'sin desbordes en ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await pump(tester, size: size);
          expect(tester.takeException(), isNull);

          // Con muchas terminales la lista se desplaza hasta la última.
          for (var i = 0; i < 12; i++) {
            repo.terminals['t$i'] = AttendanceTerminal(
              uid: 't$i',
              nombre: 'Tablet ${i.toString().padLeft(2, '0')}',
              activo: i.isEven,
            );
          }
          await repo.authorize(
            actorOf(UserRole.superadmin),
            nombre: 'Zeta',
            uid: 'z',
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, -4000));
          await tester.pumpAndSettle();
          expect(find.text('Zeta'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // El diálogo de alta también se adapta.
          await tester.tap(find.text('Autorizar terminal'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

class _NoAccounts implements StaffAccountCreator {
  @override
  Future<PendingAccount> createAccount(String email, {String? password}) =>
      throw UnimplementedError();
}
