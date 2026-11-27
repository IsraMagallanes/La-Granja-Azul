import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/inventory/models/inventory_models.dart';
import 'package:granja_azul/features/inventory/services/consumption_planner.dart';

Supply supply(String id, int stock, {bool active = true}) => Supply(
  id: id,
  name: 'Insumo $id',
  unit: SupplyUnit.kg,
  stock: stock,
  minStock: 0,
  active: active,
);

Recipe recipe(String dish, Map<String, int> items) => Recipe(dish, [
  for (final e in items.entries)
    RecipeIngredient(supplyId: e.key, name: e.key, qty: e.value),
]);

void main() {
  group('ConsumptionPlanner', () {
    test('receta × porciones, acumulado por insumo', () {
      final needs = ConsumptionPlanner.needs(
        {'d1': 2, 'd2': 1},
        {
          'd1': recipe('d1', {'a': 500, 'b': 100}),
          'd2': recipe('d2', {'a': 250}),
        },
      );
      expect(needs, {'a': 1250, 'b': 200});
    });

    test('platos sin receta o con receta vacía no descuentan y se cuentan', () {
      final recipes = <String, Recipe?>{'d1': null, 'd2': recipe('d2', {})};
      final portions = {'d1': 1, 'd2': 3, 'd3': 1};
      expect(ConsumptionPlanner.needs(portions, recipes), isEmpty);
      expect(ConsumptionPlanner.dishesWithoutRecipe(portions, recipes), 3);
      final plan = ConsumptionPlanner.plan(
        needs: const {},
        supplies: const {},
        dishesWithoutRecipe: 3,
      );
      expect(plan.lines, isEmpty);
      expect(plan.dishesWithoutRecipe, 3);
    });

    test('líneas ordenadas por insumo con el stock resultante', () {
      final plan = ConsumptionPlanner.plan(
        needs: {'b': 200, 'a': 1250},
        supplies: {'a': supply('a', 5000), 'b': supply('b', 200)},
        dishesWithoutRecipe: 0,
      );
      expect([for (final l in plan.lines) l.supply.id], ['a', 'b']);
      expect([for (final l in plan.lines) l.resulting], [3750, 0]);
    });

    test('no permite stock negativo y no descuenta nada', () {
      expect(
        () => ConsumptionPlanner.plan(
          needs: {'a': 100, 'b': 201},
          supplies: {'a': supply('a', 5000), 'b': supply('b', 200)},
          dishesWithoutRecipe: 0,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'mensaje',
            contains('Insumo b'),
          ),
        ),
      );
    });

    test('insumos inexistentes o desactivados se omiten y se cuentan', () {
      final plan = ConsumptionPlanner.plan(
        needs: {'a': 100, 'gone': 5, 'off': 5},
        supplies: {
          'a': supply('a', 1000),
          'gone': null,
          'off': supply('off', 1000, active: false),
        },
        dishesWithoutRecipe: 0,
      );
      expect(plan.lines, hasLength(1));
      expect(plan.skippedSupplies, 2);
    });

    test('más de 8 insumos distintos se rechaza', () {
      Map<String, int> needs(int n) => {for (var i = 0; i < n; i++) 'i$i': 1};
      Map<String, Supply?> supplies(int n) => {
        for (var i = 0; i < n; i++) 'i$i': supply('i$i', 1000),
      };
      expect(ConsumptionPlanner.maxSupplies, 8);
      expect(
        ConsumptionPlanner.plan(
          needs: needs(8),
          supplies: supplies(8),
          dishesWithoutRecipe: 0,
        ).lines,
        hasLength(8),
      );
      expect(
        () => ConsumptionPlanner.plan(
          needs: needs(9),
          supplies: supplies(9),
          dishesWithoutRecipe: 0,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('un consumo se lee como movimiento con su pedido', () {
      final m = StockMovement.fromMap('o1_0', {
        'insumoId': 'a',
        'insumoNombre': 'A',
        'tipo': 'consumo',
        'delta': -500,
        'stockResultante': 4500,
        'motivo': '',
        'pedidoId': 'o1',
        'creadoPorNombre': 'Cocina',
      });
      expect(m.kind, MovementKind.consumo);
      expect(m.orderId, 'o1');
    });
  });
}
