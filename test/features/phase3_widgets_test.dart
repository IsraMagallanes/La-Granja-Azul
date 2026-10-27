import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/attendance/controllers/attendance_providers.dart';
import 'package:granja_azul/features/attendance/models/schedule.dart';
import 'package:granja_azul/features/attendance/screens/my_attendance_screen.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/models/status_change.dart';
import 'package:granja_azul/features/staff/widgets/status_change_dialog.dart';

import '../support/phase3_fakes.dart';

void main() {
  group('modal de baja / suspensión', () {
    Future<StatusChange?> open(WidgetTester tester, StaffStatus target,
        {bool member = true}) async {
      StatusChange? result;
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('exige confirmación, tipo de motivo y motivo escrito', (tester) async {
      await open(tester, StaffStatus.baja);
      expect(find.text('Dar de baja'), findsOneWidget);

      // Sin confirmar, el botón está deshabilitado.
      var confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));
      expect(confirm.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));
      expect(confirm.onPressed, isNotNull);

      // Confirmado pero sin motivo: sigue abierto y muestra errores.
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pump();
      expect(find.text('Selecciona un motivo.'), findsOneWidget);
      expect(find.text('El motivo es obligatorio.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('ofrece Renuncia, Despido y Otro al dar de baja', (tester) async {
      await open(tester, StaffStatus.baja);
      await tester.tap(find.byType(DropdownButtonFormField<LeaveReason>));
      await tester.pumpAndSettle();
      expect(find.text('Renuncia'), findsWidgets);
      expect(find.text('Despido'), findsWidgets);
      expect(find.text('Otro'), findsWidgets);
    });

    testWidgets('suspender ofrece Suspensión y Otro (no Renuncia)', (tester) async {
      await open(tester, StaffStatus.suspendido);
      await tester.tap(find.byType(DropdownButtonFormField<LeaveReason>));
      await tester.pumpAndSettle();
      expect(find.text('Suspensión'), findsWidgets);
      expect(find.text('Renuncia'), findsNothing);
    });

    testWidgets('reactivar no pide tipo de motivo, pero sí texto y confirmación', (tester) async {
      await open(tester, StaffStatus.activo);
      expect(find.byType(DropdownButtonFormField<LeaveReason>), findsNothing);
      expect(find.text('Reactivar trabajador'), findsOneWidget);
    });
  });

  group('app del trabajador: QR', () {
    final worker = actorOf(UserRole.mesero, uid: 'w1');

    Future<FakeWorkerAttendanceRepository> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeWorkerAttendanceRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => Stream.value(Authenticated(worker))),
          workerAttendanceRepositoryProvider.overrideWithValue(repo),
          schedulesProvider.overrideWith((ref) => Stream.value(const <Schedule>[])),
        ],
        child: const MaterialApp(home: Scaffold(body: MyAttendanceScreen())),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('muestra QR temporal con contador; generarlo no registra asistencia', (tester) async {
      final repo = await pump(tester);
      expect(find.text('Generar QR de entrada'), findsOneWidget);
      expect(find.text('Generar QR de salida'), findsOneWidget);

      await tester.tap(find.text('Generar QR de entrada'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.tokensCreated, hasLength(1));
      expect(find.textContaining('Vence en'), findsOneWidget);
      expect(find.text('QR de entrada'), findsOneWidget);

      // Descarta el temporizador para terminar la prueba.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin entrada abierta no se puede pedir el QR de salida', (tester) async {
      final repo = await pump(tester);
      final button = tester.widget<ButtonStyleButton>(
          find.ancestor(of: find.text('Generar QR de salida'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull);
      expect(repo.tokensCreated, isEmpty);
    });
  });
}
