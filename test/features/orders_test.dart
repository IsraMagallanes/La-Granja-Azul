import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/orders/controllers/order_providers.dart';
import 'package:granja_azul/features/orders/models/order_item.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/orders/services/order_policy.dart';
import 'package:granja_azul/features/orders/services/order_service.dart';
import 'package:granja_azul/features/orders/widgets/order_detail.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/tables/controllers/table_providers.dart';
import 'package:granja_azul/features/tables/models/restaurant_table.dart';
import 'package:granja_azul/features/tables/screens/tables_screen.dart';
import 'package:granja_azul/features/tables/services/table_service.dart';

import '../support/fakes.dart';
import '../support/order_fakes.dart';

RestaurantOrder sampleOrder({OrderStatus status = OrderStatus.abierto}) =>
    RestaurantOrder(
      id: 'o',
      tableId: '1',
      waiterId: 'w1',
      waiterName: 'Ana',
      createdAt: DateTime.utc(2026, 10, 27, 17, 30),
      status: status,
      revision: 1,
      itemCount: 1,
    );
void main() {
  test(
    'número único canónico, capacidad, cantidad y observaciones válidos',
    () {
      for (final value in ['', '0', '01', '-1', '1.5', '10000']) {
        expect(TableValidation.number(value), isNotNull);
      }
      expect(TableValidation.number('25'), isNull);
      for (final value in ['0', '51', '1.5', 'abc']) {
        expect(TableValidation.capacity(value), isNotNull);
      }
      for (final value in ['0', '100', '-1', '1.5']) {
        expect(OrderValidation.quantity(value), isNotNull);
      }
      expect(OrderValidation.notes('a' * 501), isNotNull);
    },
  );
  test('precios históricos y totales calculados en centavos', () {
    final item = OrderItem.fromMap('p', {
      'nombre': 'Pollo',
      'precio': 25.5,
      'cantidad': 3,
      'observaciones': 'Sin sal',
    });
    expect(item.subtotalCents, 7650);
    expect(soles(orderTotal([item])), 'S/ 76.50');
    const fractional = OrderItem(
      dishId: 'q',
      name: 'Q',
      price: 0.1,
      quantity: 3,
      notes: '',
    );
    expect(orderTotal([fractional]), 30);
  });
  test('meseros solo pedidos propios abiertos, admins abiertos ajenos, otros solo consulta', () {
    final order = sampleOrder();
    expect(
      OrderPolicy.canEdit(buildUser(uid: 'w1', role: UserRole.mesero), order),
      true,
    );
    expect(
      OrderPolicy.canEdit(buildUser(uid: 'w2', role: UserRole.mesero), order),
      false,
    );
    for (final role in [UserRole.admin, UserRole.superadmin]) {
      expect(OrderPolicy.canEdit(buildUser(role: role), order), true);
    }
    for (final role in [UserRole.cocina, UserRole.cajero, UserRole.almacen]) {
      expect(OrderPolicy.canOpen(buildUser(role: role)), false);
    }
    expect(
      OrderPolicy.canEdit(
        buildUser(),
        sampleOrder(status: OrderStatus.registrado),
      ),
      false,
    );
    expect(OrderPolicy.canOpen(buildUser(activo: false)), false);
  });
  test(
    'servicios rechazan datos inválidos antes de acceder al repositorio',
    () async {
      final orders = FakeOrderRepository();
      final service = OrderService(orders);
      expect(() => service.add('o', 'p', 0, ''), throwsException);
      expect(orders.savedQuantity, isNull);
      await service.add('o', 'p', 2, ' sin sal ');
      expect(orders.savedNotes, 'sin sal');
      final tables = FakeTableRepository();
      expect(
        () => TableService(tables).save('01', 4, true, create: true),
        throwsException,
      );
      expect(tables.savedNumber, isNull);
      await orders.orders.close();
      await orders.items.close();
      await tables.tables.close();
    },
  );
  test('proveedor filtra las consultas por el UID del mesero', () async {
    final orders = FakeOrderRepository();
    final session = Stream<SessionState>.value(
      Authenticated(buildUser(uid: 'w1', role: UserRole.mesero)),
    );
    final container = ProviderContainer(
      overrides: [
        orderRepositoryProvider.overrideWithValue(orders),
        sessionProvider.overrideWith((ref) => session),
      ],
    );
    final subscription = container.listen(ordersProvider, (_, _) {});
    await container.read(sessionProvider.future);
    await container.read(ordersProvider.future);
    expect(orders.queriedWaiter, 'w1');
    subscription.close();
    container.dispose();
    await orders.orders.close();
    await orders.items.close();
  });
  testWidgets('mesas en vivo, ocupación y controles por rol', (tester) async {
    final tables = FakeTableRepository();
    tables.tables.add([
      const RestaurantTable(id: '1', capacity: 4, active: true),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tableRepositoryProvider.overrideWithValue(tables),
          sessionProvider.overrideWith(
            (ref) =>
                Stream.value(Authenticated(buildUser(role: UserRole.mesero))),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TablesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Libre'), findsOneWidget);
    expect(find.text('Abrir pedido'), findsOneWidget);
    expect(find.text('Nueva mesa'), findsNothing);
    tables.tables.add([
      const RestaurantTable(
        id: '1',
        capacity: 4,
        active: true,
        activeOrderId: 'o',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ocupada'), findsOneWidget);
    expect(find.text('Abrir pedido'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tables.tables.close();
  });
  testWidgets(
    'detalle muestra precios y total históricos y bloquea pedido registrado',
    (tester) async {
      final orders = FakeOrderRepository();
      orders.orders.add([sampleOrder(status: OrderStatus.registrado)]);
      orders.items.add([
        const OrderItem(
          dishId: 'p',
          name: 'Pollo',
          price: 25.5,
          quantity: 2,
          notes: 'Sin sal',
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(orders),
            sessionProvider.overrideWith(
              (ref) => Stream.value(
                Authenticated(buildUser(uid: 'w1', role: UserRole.mesero)),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: OrderDetail(orderId: 'o')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total: S/ 51.00'), findsOneWidget);
      expect(find.text('Sin sal'), findsOneWidget);
      expect(find.text('Responsable: Ana'), findsOneWidget);
      expect(find.text('Creado (Lima): 2026-10-27 12:30'), findsOneWidget);
      expect(find.text('Añadir plato'), findsNothing);
      expect(find.text('Cancelar pedido'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await orders.orders.close();
      await orders.items.close();
    },
  );
}
