import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/cashier/controllers/cash_providers.dart';
import 'package:granja_azul/features/cashier/screens/cashier_screen.dart';
import 'package:granja_azul/features/orders/controllers/order_providers.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/cashier/models/cash_models.dart';
import 'package:granja_azul/features/cashier/repositories/cash_repository.dart';
import 'package:granja_azul/features/cashier/services/cash_service.dart';
import 'package:granja_azul/features/orders/models/order_item.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';

import '../support/fakes.dart';
import '../support/order_fakes.dart';

/// Simula la transacción del cobro: o se aplica todo (pago, pedido pagado,
/// mesa libre) o nada.
class FakeCashRepository implements CashRepository {
  final payments = <String, Map<String, Object?>>{};
  final tableOwner = <String, String?>{'1': 'o1'};
  final orderState = <String, String>{'o1': 'registrado'};
  bool failNext = false;
  int chargeCalls = 0;
  Object? closed;

  @override
  Future<void> charge({
    required String orderId,
    required int totalCents,
    required PaymentMethod method,
    required int receivedCents,
    required String actorUid,
  }) async {
    chargeCalls++;
    if (failNext) {
      failNext = false;
      throw const AppFailure('Sin conexión.');
    }
    if (payments.containsKey(orderId)) {
      throw const AppFailure('Este pedido ya fue cobrado.');
    }
    payments[orderId] = {
      'total': totalCents,
      'metodo': method,
      'por': actorUid,
    };
    orderState[orderId] = 'pagado';
    tableOwner['1'] = null;
  }

  @override
  Future<void> closeBox(
    String boxId, {
    required int countedCents,
    required CashSummary summary,
    required String notes,
    required String actorUid,
  }) async => closed = (countedCents, notes);
  @override
  Future<String> openBox(int initialCents, {required String actorUid}) async =>
      'c1';
  @override
  Future<void> addMovement(
    String boxId,
    MovementType type,
    int cents,
    String concept, {
    required String actorUid,
  }) async {}
  Stream<CashBox?> Function() openStream = () => Stream.value(null);
  @override
  Stream<CashBox?> watchOpenBox() => openStream();
  @override
  Stream<List<CashBox>> watchBoxes() => Stream.value(const []);
  @override
  Stream<List<Payment>> watchPayments({String? boxId, DateTime? since}) =>
      Stream.value(const []);
  @override
  Stream<List<CashMovement>> watchMovements(String boxId) =>
      Stream.value(const []);
}

RestaurantOrder order({
  String id = 'o1',
  String table = '1',
  OrderStatus status = OrderStatus.registrado,
  KitchenStatus? kitchen = KitchenStatus.entregado,
}) => RestaurantOrder(
  id: id,
  tableId: table,
  waiterId: 'w1',
  waiterName: 'Ana',
  status: status,
  revision: 3,
  itemCount: 2,
  kitchen: kitchen,
);

const box = CashBox(
  id: 'c1',
  openedBy: 'cash',
  openedByName: 'Caja',
  initial: 10000,
  closed: false,
);

Payment pay(PaymentMethod m, int total) => Payment(
  orderId: 'p$total',
  tableId: '1',
  boxId: 'c1',
  total: total,
  method: m,
  received: total,
  change: 0,
  byName: 'Caja',
);

void main() {
  late FakeCashRepository cash;
  late FakeOrderRepository orders;
  late CashService service;

  setUp(() {
    cash = FakeCashRepository();
    orders = FakeOrderRepository();
    orders.items.add(const [
      OrderItem(
        dishId: 'a',
        name: 'Pollo',
        price: 25.5,
        quantity: 2,
        notes: '',
      ),
    ]); // 51.00
    service = CashService(cash, orders);
  });
  tearDown(() async {
    await orders.orders.close();
    await orders.items.close();
  });

  group('montos', () {
    test('Money.parse acepta soles con hasta 2 decimales', () {
      expect(Money.parse('12'), 1200);
      expect(Money.parse('12.5'), 1250);
      expect(Money.parse('12,50'), 1250);
      expect(Money.parse(' 0.05 '), 5);
      for (final bad in ['', 'abc', '-1', '1.234', '1..2', '12345678', null]) {
        expect(Money.parse(bad), isNull, reason: '$bad');
      }
      expect(Money.validate('0'), isNotNull);
      expect(Money.validate('0', allowZero: true), isNull);
    });
  });

  group('cobro', () {
    test(
      'en efectivo calcula el vuelto, libera la mesa y cierra el pedido',
      () async {
        final change = await service.charge(
          order: order(),
          box: box,
          method: PaymentMethod.efectivo,
          receivedCents: 6000,
          actorUid: 'cash',
        );
        expect(change, 900);
        expect(cash.payments['o1']!['total'], 5100);
        expect(cash.payments['o1']!['por'], 'cash');
        expect(cash.orderState['o1'], 'pagado');
        expect(cash.tableOwner['1'], isNull);
      },
    );

    test('con tarjeta, Yape o Plin cobra el total exacto sin vuelto', () async {
      for (final m in [
        PaymentMethod.tarjeta,
        PaymentMethod.yape,
        PaymentMethod.plin,
      ]) {
        final repo = FakeCashRepository();
        final change = await CashService(repo, orders).charge(
          order: order(),
          box: box,
          method: m,
          receivedCents: 99999,
          actorUid: 'cash',
        );
        expect(change, 0);
        expect(repo.payments['o1']!['total'], 5100);
      }
    });

    test('efectivo insuficiente: no cobra ni libera', () async {
      await expectLater(
        service.charge(
          order: order(),
          box: box,
          method: PaymentMethod.efectivo,
          receivedCents: 5000,
          actorUid: 'cash',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(cash.chargeCalls, 0);
      expect(cash.tableOwner['1'], 'o1');
    });

    test(
      'si el cobro falla la mesa sigue ocupada y se puede reintentar',
      () async {
        cash.failNext = true;
        await expectLater(
          service.charge(
            order: order(),
            box: box,
            method: PaymentMethod.efectivo,
            receivedCents: 6000,
            actorUid: 'cash',
          ),
          throwsA(isA<AppFailure>()),
        );
        expect(cash.payments, isEmpty);
        expect(cash.orderState['o1'], 'registrado');
        expect(cash.tableOwner['1'], 'o1');
        await service.charge(
          order: order(),
          box: box,
          method: PaymentMethod.efectivo,
          receivedCents: 6000,
          actorUid: 'cash',
        );
        expect(cash.tableOwner['1'], isNull);
        expect(cash.payments, hasLength(1));
      },
    );

    test('el mismo pedido no se cobra dos veces', () async {
      await service.charge(
        order: order(),
        box: box,
        method: PaymentMethod.efectivo,
        receivedCents: 6000,
        actorUid: 'cash',
      );
      await expectLater(
        service.charge(
          order: order(status: OrderStatus.pagado),
          box: box,
          method: PaymentMethod.efectivo,
          receivedCents: 6000,
          actorUid: 'cash',
        ),
        throwsA(isA<AppFailure>()),
      );
      // aunque el cliente tenga el pedido desactualizado, el repositorio lo rechaza
      await expectLater(
        service.charge(
          order: order(),
          box: box,
          method: PaymentMethod.efectivo,
          receivedCents: 6000,
          actorUid: 'cash2',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(cash.payments, hasLength(1));
      expect(cash.payments['o1']!['por'], 'cash');
    });

    test('exige caja abierta y pedido registrado y entregado', () async {
      Future<void> attempt(RestaurantOrder o, CashBox? b) => service.charge(
        order: o,
        box: b,
        method: PaymentMethod.efectivo,
        receivedCents: 6000,
        actorUid: 'cash',
      );
      await expectLater(attempt(order(), null), throwsA(isA<AppFailure>()));
      for (final o in [
        order(kitchen: KitchenStatus.listo),
        order(kitchen: KitchenStatus.pendiente),
        order(status: OrderStatus.abierto, kitchen: null),
        order(status: OrderStatus.cancelado, kitchen: null),
      ]) {
        await expectLater(attempt(o, box), throwsA(isA<AppFailure>()));
      }
      expect(cash.chargeCalls, 0);
    });

    test('un pedido sin total no se cobra', () async {
      orders.items.add(const []);
      await expectLater(
        service.charge(
          order: order(),
          box: box,
          method: PaymentMethod.tarjeta,
          receivedCents: 0,
          actorUid: 'cash',
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('caja', () {
    test('resumen: esperado = fondo + efectivo + ingresos − egresos', () {
      final s = CashSummary.from(
        initial: 10000,
        payments: [
          pay(PaymentMethod.efectivo, 5100),
          pay(PaymentMethod.yape, 3000),
          pay(PaymentMethod.tarjeta, 2000),
        ],
        movements: const [
          CashMovement(
            id: 'm1',
            boxId: 'c1',
            type: MovementType.ingreso,
            amount: 500,
            concept: 'Sencillo',
            byName: 'x',
          ),
          CashMovement(
            id: 'm2',
            boxId: 'c1',
            type: MovementType.egreso,
            amount: 2000,
            concept: 'Hielo',
            byName: 'x',
          ),
        ],
      );
      expect(s.cashSales, 5100);
      expect(s.otherSales, 5000);
      expect(s.totalSales, 10100);
      expect(s.salesCount, 3);
      expect(s.expectedCash, 10000 + 5100 + 500 - 2000);
      expect(s.byMethod[PaymentMethod.yape], 3000);
    });

    test('el fondo inicial y los movimientos se validan', () async {
      await expectLater(
        service.openBox(-1, actorUid: 'cash'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.openBox(10000001, actorUid: 'cash'),
        throwsA(isA<AppFailure>()),
      );
      expect(await service.openBox(0, actorUid: 'cash'), 'c1');
      for (final (amount, concept) in [
        (0, 'Hielo'),
        (10000001, 'Hielo'),
        (100, 'ab'),
        (100, '  '),
      ]) {
        await expectLater(
          service.addMovement(
            box,
            MovementType.egreso,
            amount,
            concept,
            actorUid: 'cash',
          ),
          throwsA(isA<AppFailure>()),
        );
      }
      await service.addMovement(
        box,
        MovementType.egreso,
        100,
        'Hielo',
        actorUid: 'cash',
      );
    });

    test('cierre cuadrado no exige nota; con diferencia sí', () async {
      final payments = [pay(PaymentMethod.efectivo, 5100)];
      await expectLater(
        service.closeBox(
          box,
          countedCents: 15000,
          payments: payments,
          movements: const [],
          notes: '',
          actorUid: 'cash',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(cash.closed, isNull);
      await service.closeBox(
        box,
        countedCents: 15100,
        payments: payments,
        movements: const [],
        notes: '',
        actorUid: 'cash',
      );
      expect(cash.closed, (15100, ''));
      await service.closeBox(
        box,
        countedCents: 15000,
        payments: payments,
        movements: const [],
        notes: 'Faltó sencillo',
        actorUid: 'cash',
      );
      expect(cash.closed, (15000, 'Faltó sencillo'));
    });
  });

  group('pantalla', () {
    Future<void> pump(
      WidgetTester tester, {
      bool open = true,
      Size size = const Size(1300, 900),
      UserRole role = UserRole.cajero,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (open) cash.openStream = () => Stream.value(box);
      orders.orders.add([
        order(),
        order(id: 'o2', table: '2', kitchen: KitchenStatus.listo),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(orders),
            cashRepositoryProvider.overrideWithValue(cash),
            sessionProvider.overrideWith(
              (ref) => Stream.value(
                Authenticated(buildUser(uid: 'cash', role: role)),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CashierScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('navegación vertical propia en pantallas anchas', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(NavigationRail), findsOneWidget);
      for (final l in ['Cobrar', 'Caja', 'Ventas', 'Historial']) {
        expect(find.text(l), findsWidgets);
      }
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay cajas registradas.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en celular usa barra inferior y no se desborda', (
      tester,
    ) async {
      await pump(tester, size: const Size(390, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final l in ['Caja', 'Ventas', 'Historial']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(l),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: l);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lista solo los pedidos entregados para cobrar', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Mesa 1'), findsWidgets);
      expect(find.text('Cobrar'), findsWidgets);
      expect(find.text('Aún no entregados'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con la caja cerrada no deja cobrar y ofrece abrirla', (
      tester,
    ) async {
      await pump(tester, open: false);
      expect(
        find.text('La caja está cerrada: ábrela para cobrar.'),
        findsOneWidget,
      );
      final charge = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Cobrar'),
      );
      expect(charge.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cobrar en efectivo muestra el vuelto y confirma', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrar · Mesa 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '60');
      await tester.pump();
      expect(find.text('Vuelto: S/ 9.00'), findsOneWidget);
      await tester.tap(find.text('Confirmar cobro'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(cash.payments['o1']!['total'], 5100);
      expect(find.textContaining('cobrada y liberada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si el cobro falla el diálogo sigue abierto con el motivo', (
      tester,
    ) async {
      await pump(tester);
      cash.failNext = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.text('Confirmar cobro'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cobrar · Mesa 1'), findsOneWidget);
      expect(cash.payments, isEmpty);
      expect(cash.tableOwner['1'], 'o1');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('permisos', () {
    const permissions = PermissionService();
    test('Caja, Admin y Superadmin cobran; mesero, cocina y almacén no', () {
      for (final role in UserRole.values) {
        final allowed = [
          UserRole.cajero,
          UserRole.admin,
          UserRole.superadmin,
        ].contains(role);
        for (final action in [
          PermissionAction.read,
          PermissionAction.create,
          PermissionAction.update,
        ]) {
          expect(
            permissions.canDo(role, AppModule.cashier, action),
            allowed,
            reason: '${role.name}.${action.name}',
          );
        }
      }
    });
  });
}
