import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/kitchen/screens/kitchen_screen.dart';
import 'package:granja_azul/features/kitchen/services/kitchen_policy.dart';
import 'package:granja_azul/features/orders/controllers/order_providers.dart';
import 'package:granja_azul/features/orders/models/order_item.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/orders/services/order_service.dart';
import 'package:granja_azul/features/orders/widgets/order_detail.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';

import '../support/fakes.dart';
import '../support/order_fakes.dart';

RestaurantOrder order({
  String id = 'o1',
  String table = '1',
  String waiter = 'w1',
  OrderStatus status = OrderStatus.registrado,
  KitchenStatus? kitchen = KitchenStatus.pendiente,
  DateTime? registeredAt,
}) => RestaurantOrder(
  id: id,
  tableId: table,
  waiterId: waiter,
  waiterName: 'Ana',
  status: status,
  revision: 3,
  itemCount: 1,
  kitchen: status == OrderStatus.registrado ? kitchen : null,
  registeredAt: registeredAt,
);

void main() {
  final now = DateTime.utc(2026, 11, 19, 18); // 13:00 Lima

  group('modelo', () {
    Map<String, dynamic> doc(Map<String, dynamic> extra) => {
      'mesaId': '1',
      'meseroId': 'w1',
      'meseroNombre': 'Ana',
      'estado': 'registrado',
      'revision': 2,
      'cantidadDetalles': 1,
      ...extra,
    };

    test('un pedido registrado antes de la Fase 5 cuenta como pendiente', () {
      expect(
        RestaurantOrder.fromMap('a', doc({})).kitchen,
        KitchenStatus.pendiente,
      );
    });
    test('lee el estado de cocina y solo existe en pedidos registrados', () {
      expect(
        RestaurantOrder.fromMap('a', doc({'estadoCocina': 'listo'})).kitchen,
        KitchenStatus.listo,
      );
      expect(
        RestaurantOrder.fromMap('a', doc({'estado': 'abierto'})).kitchen,
        isNull,
      );
      expect(
        RestaurantOrder.fromMap('a', doc({'estado': 'cancelado'})).kitchen,
        isNull,
      );
    });
    test('el avance es lineal y termina en entregado', () {
      expect(KitchenStatus.pendiente.next, KitchenStatus.preparando);
      expect(KitchenStatus.preparando.next, KitchenStatus.listo);
      expect(KitchenStatus.listo.next, KitchenStatus.entregado);
      expect(KitchenStatus.entregado.next, isNull);
    });
  });

  group('política', () {
    final cook = buildUser(uid: 'k', role: UserRole.cocina);
    final waiter = buildUser(uid: 'w1', role: UserRole.mesero);
    final other = buildUser(uid: 'w2', role: UserRole.mesero);
    final admin = buildUser(uid: 'a', role: UserRole.admin);
    final cashier = buildUser(uid: 'c', role: UserRole.cajero);

    test('cocina prepara y marca listo, pero no entrega', () {
      final o = order();
      expect(
        KitchenPolicy.canAdvance(cook, o, KitchenStatus.preparando),
        isTrue,
      );
      expect(
        KitchenPolicy.canAdvance(
          cook,
          order(kitchen: KitchenStatus.preparando),
          KitchenStatus.listo,
        ),
        isTrue,
      );
      expect(
        KitchenPolicy.canAdvance(
          cook,
          order(kitchen: KitchenStatus.listo),
          KitchenStatus.entregado,
        ),
        isFalse,
      );
    });
    test(
      'solo se puede pasar al estado siguiente, nunca saltar ni retroceder',
      () {
        final o = order();
        expect(KitchenPolicy.canAdvance(cook, o, KitchenStatus.listo), isFalse);
        expect(
          KitchenPolicy.canAdvance(cook, o, KitchenStatus.pendiente),
          isFalse,
        );
        expect(
          KitchenPolicy.canAdvance(admin, o, KitchenStatus.entregado),
          isFalse,
        );
      },
    );
    test('entrega el mesero responsable o la administración', () {
      final ready = order(kitchen: KitchenStatus.listo);
      expect(
        KitchenPolicy.canAdvance(waiter, ready, KitchenStatus.entregado),
        isTrue,
      );
      expect(
        KitchenPolicy.canAdvance(other, ready, KitchenStatus.entregado),
        isFalse,
      );
      expect(
        KitchenPolicy.canAdvance(admin, ready, KitchenStatus.entregado),
        isTrue,
      );
    });
    test('el mesero no mueve la cocina; caja ni inactivos nada', () {
      expect(
        KitchenPolicy.canAdvance(waiter, order(), KitchenStatus.preparando),
        isFalse,
      );
      expect(
        KitchenPolicy.canAdvance(cashier, order(), KitchenStatus.preparando),
        isFalse,
      );
      expect(
        KitchenPolicy.canAdvance(
          buildUser(uid: 'k', role: UserRole.cocina, activo: false),
          order(),
          KitchenStatus.preparando,
        ),
        isFalse,
      );
    });
    test('un pedido que no está registrado no entra a la cocina', () {
      for (final s in [OrderStatus.abierto, OrderStatus.cancelado]) {
        expect(
          KitchenPolicy.canAdvance(
            admin,
            order(status: s),
            KitchenStatus.preparando,
          ),
          isFalse,
        );
      }
    });
    test('la cola muestra solo registrados del estado pedido, el más antiguo primero', () {
      final a = order(
        id: 'a',
        registeredAt: now.subtract(const Duration(minutes: 5)),
      );
      final b = order(
        id: 'b',
        registeredAt: now.subtract(const Duration(minutes: 20)),
      );
      final c = order(id: 'c', kitchen: KitchenStatus.listo, registeredAt: now);
      final d = order(id: 'd', status: OrderStatus.abierto);
      final e = order(id: 'e', status: OrderStatus.cancelado);
      final ids = KitchenPolicy.queue([
        a,
        b,
        c,
        d,
        e,
      ], KitchenStatus.pendiente).map((o) => o.id).toList();
      expect(ids, ['b', 'a']);
      expect(
        KitchenPolicy.queue([a, b, c, d, e], KitchenStatus.listo).single.id,
        'c',
      );
    });
    test('minutos de espera y urgencia', () {
      final o = order(registeredAt: now.subtract(const Duration(minutes: 16)));
      expect(KitchenPolicy.minutesWaiting(o, now), 16);
      expect(KitchenPolicy.minutesWaiting(order(), now), 0); // sin hora
      expect(
        KitchenPolicy.minutesWaiting(
          order(registeredAt: now.add(const Duration(minutes: 3))),
          now,
        ),
        0,
      ); // reloj adelantado
      expect(KitchenPolicy.urgency(14), KitchenUrgency.normal);
      expect(KitchenPolicy.urgency(15), KitchenUrgency.attention);
      expect(KitchenPolicy.urgency(29), KitchenUrgency.attention);
      expect(KitchenPolicy.urgency(30), KitchenUrgency.late);
    });
  });

  group('servicio', () {
    test(
      'avanza un pedido registrado al siguiente estado con quien lo hizo',
      () async {
        final repository = FakeOrderRepository();
        final service = OrderService(repository);
        await service.advanceKitchen(order(), KitchenStatus.preparando, 'k');
        expect(repository.kitchenOrder, 'o1');
        expect(repository.kitchenTo, KitchenStatus.preparando);
        expect(repository.kitchenActor, 'k');
        await repository.orders.close();
        await repository.items.close();
      },
    );
    test('rechaza saltos y pedidos que no están en cocina', () async {
      final repository = FakeOrderRepository();
      final service = OrderService(repository);
      for (final (o, to) in [
        (order(), KitchenStatus.listo),
        (order(kitchen: KitchenStatus.entregado), KitchenStatus.entregado),
        (order(status: OrderStatus.abierto), KitchenStatus.preparando),
      ]) {
        await expectLater(
          service.advanceKitchen(o, to, 'k'),
          throwsA(isA<AppFailure>()),
        );
      }
      expect(repository.kitchenTo, isNull);
      await repository.orders.close();
      await repository.items.close();
    });
  });

  group('pantalla', () {
    late FakeOrderRepository repository;

    setUp(() => repository = FakeOrderRepository());
    tearDown(() async {
      await repository.orders.close();
      await repository.items.close();
    });

    Future<void> pump(
      WidgetTester tester,
      List<RestaurantOrder> orders, {
      UserRole role = UserRole.cocina,
      String uid = 'k',
      Size size = const Size(1300, 900),
      Widget home = const KitchenScreen(),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repository.orders.add(orders);
      repository.items.add(const [
        OrderItem(
          dishId: 'p',
          name: 'Pollo a la brasa',
          price: 25.5,
          quantity: 2,
          notes: 'Sin sal',
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(repository),
            sessionProvider.overrideWith(
              (ref) =>
                  Stream.value(Authenticated(buildUser(uid: uid, role: role))),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('tres columnas con los pedidos registrados y su detalle', (
      tester,
    ) async {
      await pump(tester, [
        order(id: 'a', table: '1'),
        order(id: 'b', table: '2', kitchen: KitchenStatus.preparando),
        order(id: 'c', table: '3', kitchen: KitchenStatus.listo),
        order(id: 'x', table: '4', kitchen: KitchenStatus.entregado),
        order(id: 'y', table: '5', status: OrderStatus.abierto),
        order(id: 'z', table: '6', status: OrderStatus.cancelado),
      ]);
      for (final t in ['1', '2', '3']) {
        expect(find.text('Mesa $t'), findsOneWidget);
      }
      for (final t in ['4', '5', '6']) {
        expect(
          find.text('Mesa $t'),
          findsNothing,
        ); // entregado, abierto, cancelado
      }
      expect(find.text('2 × Pollo a la brasa\n   ↳ Sin sal'), findsNWidgets(3));
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('En preparación'), findsOneWidget);
      await close(tester);
    });

    testWidgets('cocina empieza a preparar y marca listo; no entrega', (
      tester,
    ) async {
      await pump(tester, [
        order(id: 'a', table: '1'),
        order(id: 'b', table: '2', kitchen: KitchenStatus.preparando),
        order(id: 'c', table: '3', kitchen: KitchenStatus.listo),
      ]);
      await tester.tap(find.text('Empezar a preparar'));
      await tester.pumpAndSettle();
      expect(repository.kitchenOrder, 'a');
      expect(repository.kitchenTo, KitchenStatus.preparando);
      expect(repository.kitchenActor, 'k');
      await tester.tap(find.text('Marcar listo'));
      await tester.pumpAndSettle();
      expect(repository.kitchenOrder, 'b');
      expect(repository.kitchenTo, KitchenStatus.listo);
      expect(find.text('Marcar entregado'), findsNothing);
      expect(find.text('Listo: espera al mesero.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('el admin supervisa y también puede entregar', (tester) async {
      await pump(
        tester,
        [order(kitchen: KitchenStatus.listo)],
        role: UserRole.admin,
        uid: 'a',
      );
      await tester.tap(find.text('Marcar entregado'));
      await tester.pumpAndSettle();
      expect(repository.kitchenTo, KitchenStatus.entregado);
      await close(tester);
    });

    testWidgets('quien solo consulta no ve botones', (tester) async {
      await pump(tester, [order()], role: UserRole.cajero, uid: 'c');
      expect(find.text('Mesa 1'), findsOneWidget);
      expect(find.text('Empezar a preparar'), findsNothing);
      await close(tester);
    });

    testWidgets('el tiempo de espera y la urgencia se ven en el pedido', (
      tester,
    ) async {
      final now = DateTime.now();
      await pump(tester, [
        order(
          id: 'a',
          table: '1',
          registeredAt: now.subtract(const Duration(minutes: 5)),
        ),
        order(
          id: 'b',
          table: '2',
          registeredAt: now.subtract(const Duration(minutes: 35)),
        ),
      ]);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('35 min'), findsOneWidget);
      // El más antiguo va primero.
      expect(
        tester.getTopLeft(find.text('Mesa 2')).dy,
        lessThan(tester.getTopLeft(find.text('Mesa 1')).dy),
      );
      await close(tester);
    });

    testWidgets('en pantalla angosta muestra una columna a la vez', (
      tester,
    ) async {
      await pump(tester, [
        order(id: 'a', table: '1'),
        order(id: 'b', table: '2', kitchen: KitchenStatus.preparando),
      ], size: const Size(420, 900));
      expect(find.text('Mesa 1'), findsOneWidget);
      expect(find.text('Mesa 2'), findsNothing);
      await tester.tap(find.text('En preparación (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Mesa 2'), findsOneWidget);
      expect(find.text('Mesa 1'), findsNothing);
      await close(tester);
    });

    testWidgets('sin pedidos muestra el estado vacío', (tester) async {
      await pump(tester, const []);
      expect(find.text('Sin pedidos aquí.'), findsNWidgets(3));
      await close(tester);
    });

    testWidgets(
      'el mesero responsable marca entregado desde el detalle del pedido',
      (tester) async {
        await pump(
          tester,
          [order(kitchen: KitchenStatus.listo)],
          role: UserRole.mesero,
          uid: 'w1',
          home: const OrderDetail(orderId: 'o1'),
        );
        expect(find.text('Cocina: Listo'), findsOneWidget);
        await tester.tap(find.text('Marcar entregado'));
        await tester.pumpAndSettle();
        expect(repository.kitchenTo, KitchenStatus.entregado);
        expect(repository.kitchenActor, 'w1');
        await close(tester);
      },
    );

    testWidgets('otro mesero no ve el botón de entregar', (tester) async {
      await pump(
        tester,
        [order(kitchen: KitchenStatus.listo)],
        role: UserRole.mesero,
        uid: 'w2',
        home: const OrderDetail(orderId: 'o1'),
      );
      expect(find.text('Marcar entregado'), findsNothing);
      await close(tester);
    });
  });
}
