import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/roles/screens/roles_screen.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: RolesScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'muestra la matriz del rol elegido y su condición de asistencia',
    (tester) async {
      await pump(tester);
      // Mesero por defecto: requiere entrada; ve pedidos y nadie ve «Terminales».
      expect(find.text('Requiere entrada'), findsOneWidget);
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Terminales'), findsNothing);

      await tester.tap(find.text('Administrador'));
      await tester.pumpAndSettle();
      expect(find.text('Exento'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Terminales'), findsNothing);

      await tester.tap(find.text('Superadministrador'));
      await tester.pumpAndSettle();
      expect(find.text('Exento'), findsOneWidget);
      expect(find.text('Terminales'), findsNothing);
      expect(find.text('Auditoría'), findsOneWidget);
    },
  );

  testWidgets('es de solo lectura: sin controles que modifiquen permisos', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('Solo lectura'), findsOneWidget);
  });

  testWidgets('sin desbordes en celular', (tester) async {
    await pump(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
