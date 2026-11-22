import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/inventory/controllers/inventory_providers.dart';
import 'package:granja_azul/features/inventory/models/inventory_models.dart';
import 'package:granja_azul/features/inventory/repositories/inventory_repository.dart';
import 'package:granja_azul/features/inventory/screens/inventory_screen.dart';
import 'package:granja_azul/features/inventory/services/inventory_service.dart';
import 'package:granja_azul/features/menu/controllers/menu_providers.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:rxdart/rxdart.dart';

import '../support/fakes.dart';

class FakeInventoryRepository implements InventoryRepository {
  final supplies = BehaviorSubject<List<Supply>>.seeded([]);
  final moves = <(String, MovementKind, int, String)>[];
  final purchases = BehaviorSubject<List<Purchase>>.seeded([]);
  final received = <String>[];
  Supply? created;
  List<PurchaseLine>? purchaseLines;
  Map<String, int>? saved;

  @override
  Stream<List<Supply>> watchSupplies() => supplies.stream;
  @override
  Stream<List<StockMovement>> watchMovements() => Stream.value(const []);
  @override
  Stream<List<Supplier>> watchSuppliers() => Stream.value(const []);
  @override
  Stream<List<Purchase>> watchPurchases() => purchases.stream;
  @override
  Stream<List<Recipe>> watchRecipes() => Stream.value(const []);
  @override
  Future<void> createSupply(
    String name,
    SupplyUnit unit,
    int minStock,
    int unitCost,
  ) async => created = Supply(
    id: 'n',
    name: name,
    unit: unit,
    stock: 0,
    minStock: minStock,
    unitCost: unitCost,
    active: true,
  );
  @override
  Future<void> editSupply(
    String id, {
    required String name,
    required int minStock,
    required int unitCost,
    required bool active,
  }) async {}
  @override
  Future<void> moveStock(
    String supplyId,
    MovementKind kind,
    int delta,
    String reason, {
    required String actorUid,
  }) async => moves.add((supplyId, kind, delta, reason));
  @override
  Future<void> saveSupplier(
    String? id, {
    required String name,
    required String ruc,
    required String phone,
    required String contact,
    required bool active,
  }) async {}
  @override
  Future<void> createPurchase(
    Supplier supplier,
    List<PurchaseLine> lines, {
    required String actorUid,
  }) async => purchaseLines = lines;
  @override
  Future<void> receivePurchase(String id, {required String actorUid}) async =>
      received.add(id);
  @override
  Future<void> cancelPurchase(
    String id,
    String reason, {
    required String actorUid,
  }) async {}
  @override
  Future<void> saveRecipe(
    String dishId,
    List<RecipeIngredient> ingredients, {
    required String actorUid,
  }) async => saved = {for (final i in ingredients) i.supplyId: i.qty};
}

Supply supply({
  String id = 'i1',
  int stock = 10000,
  int min = 2000,
  int cost = 1200,
  bool active = true,
  SupplyUnit unit = SupplyUnit.kg,
}) => Supply(
  id: id,
  name: 'Pollo',
  unit: unit,
  stock: stock,
  minStock: min,
  unitCost: cost,
  active: active,
);

const supplier = Supplier(
  id: 'p1',
  name: 'Avícola',
  ruc: '',
  phone: '',
  contact: '',
  active: true,
);

PurchaseLine line(String id, {int qty = 4000, int cost = 1250}) =>
    PurchaseLine(supplyId: id, name: id, qty: qty, unitCost: cost);

Purchase purchase({
  PurchaseStatus status = PurchaseStatus.pendiente,
  String createdBy = 'creador',
  int invalidLines = 0,
}) => Purchase(
  id: 'c1',
  supplierId: 'p1',
  supplierName: 'Avícola',
  lines: [line('i1')],
  status: status,
  byName: 'Luis',
  createdBy: createdBy,
  invalidLines: invalidLines,
);

void main() {
  late FakeInventoryRepository repo;
  late InventoryService service;
  setUp(() {
    repo = FakeInventoryRepository();
    service = InventoryService(repo);
  });
  tearDown(() async {
    await repo.supplies.close();
    await repo.purchases.close();
  });

  group('cantidades', () {
    test('Qty.parse y format usan milésimas enteras', () {
      expect(Qty.parse('1.5'), 1500);
      expect(Qty.parse('2'), 2000);
      expect(Qty.parse('0,125'), 125);
      for (final bad in ['', 'x', '-1', '1.2345', '1234567', null]) {
        expect(Qty.parse(bad), isNull, reason: '$bad');
      }
      expect(Qty.format(1500), '1.5');
      expect(Qty.format(2000), '2');
      expect(Qty.format(125), '0.125');
      expect(Qty.validate('0'), isNotNull);
      expect(Qty.validate('0', allowZero: true), isNull);
    });

    test('costo de una cantidad redondea a centavos', () {
      expect(Qty.cost(1500, 1200), 1800); // 1.5 kg a S/ 12.00
      expect(Qty.cost(125, 1200), 150);
      expect(Qty.cost(0, 1200), 0);
    });
  });

  group('insumos y recetas', () {
    test('stock bajo, agotado y etiqueta', () {
      expect(supply(stock: 2000).isLow, isTrue);
      expect(supply(stock: 2001).isLow, isFalse);
      expect(supply(stock: 0).isOut, isTrue);
      expect(supply(min: 0, stock: 0).isLow, isFalse);
      expect(supply(active: false, stock: 0).isLow, isFalse);
      expect(supply(stock: 1500).stockLabel, '1.5 kg');
    });

    test('costo de una receta con el costo vigente y margen', () {
      final pollo = supply(cost: 1200);
      final papa = supply(id: 'i2', cost: 300);
      final recipe = Recipe('d1', const [
        RecipeIngredient(supplyId: 'i1', name: 'Pollo', qty: 500),
        RecipeIngredient(supplyId: 'i2', name: 'Papa', qty: 300),
      ]);
      final map = {'i1': pollo, 'i2': papa};
      expect(recipe.cost(map), 600 + 90);
      expect(recipe.hasMissing(map), isFalse);
      expect(recipe.cost({'i1': pollo}), 600); // insumo faltante = 0
      expect(recipe.hasMissing({'i1': pollo}), isTrue);
      expect(Recipe.margin(2550, 690), 1860);
    });
  });

  group('movimientos de stock', () {
    test(
      'entrada suma, salida y merma restan, ajuste usa el signo elegido',
      () async {
        await service.moveStock(
          supply(),
          MovementKind.entrada,
          2000,
          'Conteo del día',
          actorUid: 'a',
        );
        await service.moveStock(
          supply(),
          MovementKind.salida,
          1000,
          'Cocina',
          actorUid: 'a',
        );
        await service.moveStock(
          supply(),
          MovementKind.merma,
          500,
          'Vencido',
          actorUid: 'a',
        );
        await service.moveStock(
          supply(),
          MovementKind.ajuste,
          300,
          'Conteo',
          increase: false,
          actorUid: 'a',
        );
        await service.moveStock(
          supply(),
          MovementKind.ajuste,
          300,
          'Conteo',
          actorUid: 'a',
        );
        expect(repo.moves.map((m) => m.$3), [2000, -1000, -500, -300, 300]);
      },
    );

    test('rechaza stock negativo, cantidades nulas, motivo faltante y compras manuales', () async {
      Future<void> attempt(MovementKind k, int q, String reason, {Supply? s}) =>
          service.moveStock(s ?? supply(), k, q, reason, actorUid: 'a');
      await expectLater(
        attempt(MovementKind.salida, 10001, 'Cocina'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.entrada, 0, 'Conteo'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.salida, 100, ''),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.merma, 100, 'ab'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.compra, 100, 'x'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.entrada, 100, 'Conteo', s: supply(active: false)),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(MovementKind.entrada, Qty.max, 'Conteo'),
        throwsA(isA<AppFailure>()),
      );
      // Las entradas manuales también exigen motivo.
      for (final r in ['', '  ', 'ab']) {
        await expectLater(
          attempt(MovementKind.entrada, 100, r),
          throwsA(isA<AppFailure>()),
        );
      }
      expect(repo.moves, isEmpty);
    });

    test('valida el alta de un insumo', () async {
      await expectLater(
        service.createSupply('a', SupplyUnit.kg, 0, 0),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.createSupply('Aceite', SupplyUnit.l, -1, 0),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.createSupply(
          'Aceite',
          SupplyUnit.l,
          0,
          InventoryValidation.maxCost + 1,
        ),
        throwsA(isA<AppFailure>()),
      );
      await service.createSupply('  Aceite ', SupplyUnit.l, 1000, 800);
      expect(repo.created!.name, 'Aceite');
    });
  });

  group('proveedores y compras', () {
    test('RUC de 11 dígitos o vacío', () async {
      expect(InventoryValidation.ruc(''), isNull);
      expect(InventoryValidation.ruc('20123456789'), isNull);
      expect(InventoryValidation.ruc('123'), isNotNull);
      await expectLater(
        service.saveSupplier(
          null,
          name: 'SAC',
          ruc: '12',
          phone: '',
          contact: '',
          active: true,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('una compra necesita proveedor activo, líneas válidas y sin repetir insumos', () async {
      Future<void> attempt(Supplier? s, List<PurchaseLine> l) =>
          service.createPurchase(s, l, actorUid: 'a');
      await expectLater(
        attempt(null, [line('i1')]),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(
          const Supplier(
            id: 'p',
            name: 'X',
            ruc: '',
            phone: '',
            contact: '',
            active: false,
          ),
          [line('i1')],
        ),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(attempt(supplier, []), throwsA(isA<AppFailure>()));
      await expectLater(
        attempt(supplier, [line('i1'), line('i1')]),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(supplier, [line('i1', qty: 0)]),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        attempt(supplier, [for (var i = 0; i < 9; i++) line('i$i')]),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.purchaseLines, isNull);
      expect(InventoryValidation.maxLines, 8);
      await attempt(supplier, [for (var i = 0; i < 8; i++) line('i$i')]);
      expect(repo.purchaseLines, hasLength(8));
      await attempt(supplier, [line('i1'), line('i2')]);
      expect(repo.purchaseLines, hasLength(2));
      expect(line('i1').subtotal, 5000); // 4 kg a S/ 12.50
    });

    test(
      'quien crea la compra no la recibe, salvo Admin y Superadmin',
      () async {
        await expectLater(
          service.receivePurchase(purchase(), actorUid: 'creador'),
          throwsA(isA<AppFailure>()),
        );
        expect(repo.received, isEmpty);
        await service.receivePurchase(
          purchase(),
          actorUid: 'creador',
          isAdmin: true,
        );
        expect(repo.received, ['c1']);
      },
    );

    test('una compra con líneas ilegibles no se recibe', () async {
      await expectLater(
        service.receivePurchase(purchase(invalidLines: 1), actorUid: 'otro'),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.received, isEmpty);
    });

    test('lectura tolerante de compras y recetas alteradas', () {
      final p = Purchase.fromMap('c9', {
        'proveedorId': 'p1',
        'proveedorNombre': 'Avícola',
        'estado': 'pendiente',
        'lineas': [
          {
            'insumoId': 'i1',
            'nombre': 'Pollo',
            'cantidad': 4000,
            'costoUnitario': 1250,
          },
          'basura',
          {'insumoId': 'i2', 'cantidad': -5},
          42,
        ],
      });
      expect(p.lines, hasLength(1));
      expect(p.invalidLines, 3);
      expect(p.total, 5000); // se deriva de las líneas
      expect(Purchase.fromMap('c0', {'estado': 'x'}).invalidLines, 1);
      final r = Recipe.fromMap('d1', {
        'ingredientes': [
          {'insumoId': 'i1', 'nombre': 'Pollo', 'cantidad': 500},
          'basura',
          {'insumoId': 'i1', 'nombre': 'Pollo', 'cantidad': 'x'},
        ],
      });
      expect(r.ingredients, hasLength(1));
      expect(Recipe.fromMap('d2', {'ingredientes': 7}).ingredients, isEmpty);
    });

    test('solo se recibe o cancela una compra pendiente', () async {
      await service.receivePurchase(purchase(), actorUid: 'otro');
      expect(repo.received, ['c1']);
      for (final s in [PurchaseStatus.recibida, PurchaseStatus.cancelada]) {
        await expectLater(
          service.receivePurchase(purchase(status: s), actorUid: 'otro'),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.cancelPurchase(purchase(status: s), 'Motivo', actorUid: 'a'),
          throwsA(isA<AppFailure>()),
        );
      }
      await expectLater(
        service.cancelPurchase(purchase(), 'ab', actorUid: 'a'),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.received, hasLength(1));
    });

    test(
      'las recetas no repiten insumos ni aceptan cantidades en cero',
      () async {
        RecipeIngredient ing(String id, int q) =>
            RecipeIngredient(supplyId: id, name: id, qty: q);
        await expectLater(
          service.saveRecipe('d1', [ing('i1', 5), ing('i1', 5)], actorUid: 'a'),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.saveRecipe('d1', [ing('i1', 0)], actorUid: 'a'),
          throwsA(isA<AppFailure>()),
        );
        await service.saveRecipe('d1', [
          ing('i1', 500),
          ing('i2', 300),
        ], actorUid: 'a');
        expect(repo.saved, {'i1': 500, 'i2': 300});
      },
    );
  });

  group('permisos', () {
    test(
      'Almacén, Admin y Superadmin gestionan el inventario; el resto no',
      () {
        const permissions = PermissionService();
        for (final role in UserRole.values) {
          final allowed = [
            UserRole.almacen,
            UserRole.admin,
            UserRole.superadmin,
          ].contains(role);
          for (final a in [
            PermissionAction.read,
            PermissionAction.create,
            PermissionAction.update,
          ]) {
            expect(
              permissions.canDo(role, AppModule.inventory, a),
              allowed,
              reason: '${role.name}.${a.name}',
            );
          }
        }
      },
    );
  });

  group('pantalla', () {
    Future<void> pump(
      WidgetTester tester, {
      Size size = const Size(1100, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.supplies.add([supply(), supply(id: 'i2', stock: 1000)]);
      repo.purchases.add([purchase()]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(repo),
            menuCatalogProvider.overrideWith(
              (ref) => Stream.value(const MenuCatalog([], [])),
            ),
            sessionProvider.overrideWith(
              (ref) => Stream.value(
                Authenticated(buildUser(uid: 'st', role: UserRole.almacen)),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(
                    sessionProvider,
                  ); // como el panel real, mantiene viva la sesión
                  return const InventoryScreen();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('insumos con stock bajo y filtro', (tester) async {
      await pump(tester);
      expect(find.text('Pollo'), findsNWidgets(2));
      expect(find.text('Stock bajo'), findsOneWidget);
      await tester.tap(find.text('Stock bajo (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Pollo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('registrar una salida deja el movimiento con su motivo', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Salida').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (kg)'),
        '1.5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Servicio del día',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(repo.moves.single.$3, -1500);
      expect(repo.moves.single.$4, 'Servicio del día');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('una salida mayor al stock muestra el motivo y no guarda', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Salida').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cantidad (kg)'),
        '99',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo'),
        'Servicio del día',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No hay stock suficiente'), findsOneWidget);
      expect(repo.moves, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la pestaña Compras permite recibir una compra pendiente', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(find.text('Pendiente'), findsOneWidget);
      await tester.tap(find.text('Recibir compra'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(repo.received, ['c1']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en celular las cinco pestañas se recorren sin desbordes', (
      tester,
    ) async {
      await pump(tester, size: const Size(390, 800));
      for (final t in [
        'Movimientos',
        'Recetas',
        'Proveedores',
        'Compras',
        'Insumos',
      ]) {
        await tester.tap(find.text(t));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: t);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
