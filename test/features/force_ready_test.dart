import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/inventory/models/inventory_models.dart';
import 'package:granja_azul/features/inventory/services/consumption_planner.dart';
import 'package:granja_azul/features/kitchen/widgets/force_ready_dialog.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/orders/services/order_service.dart';

import '../support/order_fakes.dart';

Supply supply(String id, int stock, {bool active = true}) => Supply(
  id: id,
  name: 'Insumo $id',
  unit: SupplyUnit.kg,
  stock: stock,
  minStock: 0,
  unitCost: 100,
  active: active,
);

RestaurantOrder preparing() => RestaurantOrder(
  id: 'o1',
  tableId: '1',
  waiterId: 'w1',
  waiterName: 'Ana',
  status: OrderStatus.registrado,
  kitchen: KitchenStatus.preparando,
  revision: 3,
  itemCount: 1,
);

void main() {
  group('forzar «Listo» (planificador)', () {
    test('sin forzar, el faltante lanza con todos los insumos que faltan', () {
      try {
        ConsumptionPlanner.plan(
          needs: {'a': 12000, 'b': 500, 'c': 100},
          supplies: {
            'a': supply('a', 10000),
            'b': supply('b', 0),
            'c': supply('c', 100),
          },
          dishesWithoutRecipe: 0,
        );
        fail('debía lanzar');
      } on InsufficientStockFailure catch (e) {
        expect([for (final s in e.shortages) s.supply.id], ['a', 'b']);
        expect(e, isA<AppFailure>());
      }
    });

    test(
      'forzando descuenta solo lo disponible y nunca deja stock negativo',
      () {
        final plan = ConsumptionPlanner.plan(
          needs: {'a': 12000, 'b': 500, 'c': 100},
          supplies: {
            'a': supply('a', 10000),
            'b': supply('b', 0),
            'c': supply('c', 100),
          },
          dishesWithoutRecipe: 0,
          allowShortage: true,
        );
        // 'b' no tiene stock: sin movimiento, pero queda como faltante.
        expect([for (final l in plan.lines) l.supply.id], ['a', 'c']);
        expect([for (final l in plan.lines) l.qty], [10000, 100]);
        expect([for (final l in plan.lines) l.resulting], [0, 0]);
        expect([for (final s in plan.shortages) s.missing], [2000, 500]);
        for (final l in plan.lines) {
          expect(l.resulting, greaterThanOrEqualTo(0));
        }
      },
    );

    test('el faltante se registra con necesario = descontado + faltante', () {
      final s = StockShortage(supply: supply('a', 10000), needed: 12000);
      expect(s.toMap(), {
        'insumoId': 'a',
        'insumo': 'Insumo a',
        'necesario': 12000,
        'descontado': 10000,
        'faltante': 2000,
      });
    });

    test('forzar no esquiva el límite de 8 insumos ni cuenta los omitidos', () {
      final needs = {for (var i = 0; i < 9; i++) 'i$i': 1000};
      final supplies = {for (var i = 0; i < 9; i++) 'i$i': supply('i$i', 0)};
      expect(
        () => ConsumptionPlanner.plan(
          needs: needs,
          supplies: supplies,
          dishesWithoutRecipe: 0,
          allowShortage: true,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('con stock suficiente forzar no genera faltantes', () {
      final plan = ConsumptionPlanner.plan(
        needs: {'a': 100},
        supplies: {'a': supply('a', 1000)},
        dishesWithoutRecipe: 0,
        allowShortage: true,
      );
      expect(plan.shortages, isEmpty);
    });
  });

  group('forzar «Listo» (servicio)', () {
    test('el motivo exige 10 caracteres y solo se fuerza «Listo»', () async {
      final repo = FakeOrderRepository();
      final service = OrderService(repo);
      for (final r in ['', 'corto', '         x', 'x' * 201]) {
        await expectLater(
          service.advanceKitchen(
            preparing(),
            KitchenStatus.listo,
            'admin',
            forceReason: r,
          ),
          throwsA(isA<AppFailure>()),
        );
      }
      await expectLater(
        service.advanceKitchen(
          RestaurantOrder(
            id: 'o1',
            tableId: '1',
            waiterId: 'w1',
            waiterName: 'Ana',
            status: OrderStatus.registrado,
            kitchen: KitchenStatus.pendiente,
            revision: 1,
            itemCount: 1,
          ),
          KitchenStatus.preparando,
          'admin',
          forceReason: 'Motivo suficientemente largo',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.kitchenTo, isNull);
      await service.advanceKitchen(
        preparing(),
        KitchenStatus.listo,
        'admin',
        forceReason: '  Cliente esperando, repongo luego  ',
      );
      expect(repo.kitchenForceReason, 'Cliente esperando, repongo luego');
      expect(repo.kitchenTo, KitchenStatus.listo);
      await repo.orders.close();
      await repo.items.close();
    });

    test('el flujo normal no lleva motivo', () async {
      final repo = FakeOrderRepository();
      await OrderService(repo)
          .advanceKitchen(preparing(), KitchenStatus.listo, 'k');
      expect(repo.kitchenForceReason, isNull);
      await repo.orders.close();
      await repo.items.close();
    });
  });

  group('diálogo de forzado', () {
    Future<String?> open(
      WidgetTester tester,
      Future<void> Function() act,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<String>(
                context: context,
                builder: (_) => ForceReadyDialog(
                  shortages: [
                    StockShortage(supply: supply('a', 10000), needed: 12000),
                  ],
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await act();
      return result;
    }

    testWidgets('muestra los faltantes y rechaza un motivo corto', (
      tester,
    ) async {
      final result = await open(tester, () async {
        expect(find.textContaining('faltan 2'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField), 'corto');
        await tester.tap(find.text('Forzar «Listo»'));
        await tester.pumpAndSettle();
        expect(find.textContaining('10 a 200'), findsOneWidget);
      });
      expect(result, isNull);
    });

    testWidgets('devuelve el motivo recortado cuando es válido', (
      tester,
    ) async {
      final result = await open(tester, () async {
        await tester.enterText(
          find.byType(TextFormField),
          '  Cliente esperando, repongo  ',
        );
        await tester.tap(find.text('Forzar «Listo»'));
        await tester.pumpAndSettle();
      });
      expect(result, 'Cliente esperando, repongo');
    });

    testWidgets('cancelar no devuelve nada', (tester) async {
      final result = await open(tester, () async {
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      });
      expect(result, isNull);
    });
  });
}
