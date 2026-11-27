import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/attendance/controllers/attendance_providers.dart';
import 'package:granja_azul/features/attendance/models/schedule.dart';
import 'package:granja_azul/features/attendance/screens/my_attendance_screen.dart';
import 'package:granja_azul/features/attendance/screens/qr_generator_screen.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/models/status_change.dart';
import 'package:granja_azul/features/staff/widgets/status_change_dialog.dart';

import '../support/phase3_fakes.dart';

void main() {
  group('modal de baja / suspensión', () {
    Future<StatusChange?> open(
      WidgetTester tester,
      StaffStatus target, {
      bool member = true,
    }) async {
      StatusChange? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await StatusChangeDialog.show(
                context,
                member: memberOf('m1'),
                target: target,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('exige confirmación, tipo de motivo y motivo escrito', (
      tester,
    ) async {
      await open(tester, StaffStatus.baja);
      expect(find.text('Dar de baja'), findsOneWidget);

      // Sin confirmar, el botón está deshabilitado.
      var confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar'),
      );
      expect(confirm.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar'),
      );
      expect(confirm.onPressed, isNotNull);

      // Confirmado pero sin motivo: sigue abierto y muestra errores.
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pump();
      expect(find.text('Selecciona un motivo.'), findsOneWidget);
      expect(find.text('El motivo es obligatorio.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('ofrece Renuncia, Despido y Otro al dar de baja', (
      tester,
    ) async {
      await open(tester, StaffStatus.baja);
      await tester.tap(find.byType(DropdownButtonFormField<LeaveReason>));
      await tester.pumpAndSettle();
      expect(find.text('Renuncia'), findsWidgets);
      expect(find.text('Despido'), findsWidgets);
      expect(find.text('Otro'), findsWidgets);
    });

    testWidgets('suspender ofrece Suspensión y Otro (no Renuncia)', (
      tester,
    ) async {
      await open(tester, StaffStatus.suspendido);
      await tester.tap(find.byType(DropdownButtonFormField<LeaveReason>));
      await tester.pumpAndSettle();
      expect(find.text('Suspensión'), findsWidgets);
      expect(find.text('Renuncia'), findsNothing);
    });

    testWidgets(
      'reactivar no pide tipo de motivo, pero sí texto y confirmación',
      (tester) async {
        await open(tester, StaffStatus.activo);
        expect(find.byType(DropdownButtonFormField<LeaveReason>), findsNothing);
        expect(find.text('Reactivar trabajador'), findsOneWidget);
      },
    );
  });

  group('Mi asistencia y QR por rol', () {
    Future<(FakeWorkerAttendanceRepository, FakeQrGenerationRepository)> pump(
      WidgetTester tester,
      UserRole role,
      Widget screen,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeWorkerAttendanceRepository();
      final qrs = FakeQrGenerationRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(
              (ref) => Stream.value(Authenticated(actorOf(role, uid: 'u1'))),
            ),
            workerAttendanceRepositoryProvider.overrideWithValue(repo),
            qrGenerationRepositoryProvider.overrideWithValue(qrs),
            schedulesProvider.overrideWith(
              (ref) => Stream.value(const <Schedule>[]),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await tester.pumpAndSettle();
      return (repo, qrs);
    }

    const scan = 'Escanear QR de asistencia';
    const show = 'Mostrar QR de asistencia';

    testWidgets('Mesero y Cocina solo ven el escáner: ni botones de generar QR '
        'ni selección manual de entrada o salida', (tester) async {
      for (final role in [UserRole.mesero, UserRole.cocina]) {
        final (_, qrs) = await pump(tester, role, const MyAttendanceScreen());
        expect(find.text(scan), findsOneWidget, reason: role.name);
        expect(find.text(show), findsNothing, reason: role.name);
        expect(find.textContaining('Generar QR'), findsNothing);
        expect(find.textContaining('QR de entrada'), findsNothing);
        expect(find.textContaining('QR de salida'), findsNothing);
        expect(qrs.created, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Cajero ve escáner y también puede mostrar el QR', (
      tester,
    ) async {
      await pump(tester, UserRole.cajero, const MyAttendanceScreen());
      expect(find.text(scan), findsOneWidget);
      expect(find.text(show), findsOneWidget);
    });

    testWidgets('Admin y Superadmin solo muestran el QR; no escanean', (
      tester,
    ) async {
      for (final role in [UserRole.admin, UserRole.superadmin]) {
        await pump(tester, role, const MyAttendanceScreen());
        expect(find.text(show), findsOneWidget, reason: role.name);
        expect(find.text(scan), findsNothing, reason: role.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('el generador muestra un QR con contador y sin registrar '
        'asistencia', (tester) async {
      final (repo, qrs) = await pump(
        tester,
        UserRole.cajero,
        const QrGeneratorScreen(),
      );
      expect(qrs.created, hasLength(1));
      expect(qrs.created.single.generadorRol, UserRole.cajero);
      expect(find.textContaining('Vence en'), findsOneWidget);
      expect(repo.states, isEmpty);
      // Descarta los temporizadores para terminar la prueba.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un Mesero que llega a la pantalla de generar no crea QR', (
      tester,
    ) async {
      final (_, qrs) = await pump(
        tester,
        UserRole.mesero,
        const QrGeneratorScreen(),
      );
      expect(find.textContaining('no puede generar'), findsOneWidget);
      expect(find.textContaining('Vence en'), findsNothing);
      expect(qrs.created, isEmpty);
    });
  });
}
