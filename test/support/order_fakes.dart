import 'package:rxdart/rxdart.dart';
import 'package:granja_azul/features/orders/models/order_item.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/orders/repositories/order_repository.dart';
import 'package:granja_azul/features/tables/models/restaurant_table.dart';
import 'package:granja_azul/features/tables/repositories/table_repository.dart';

class FakeTableRepository implements TableRepository {
  final tables = BehaviorSubject<List<RestaurantTable>>.seeded([]);
  String? savedNumber;
  int? savedCapacity;
  bool? savedActive;
  @override
  Stream<List<RestaurantTable>> watchTables() => tables.stream;
  @override
  Future<void> saveTable(
    String number,
    int capacity,
    bool active, {
    required bool create,
  }) async {
    savedNumber = number;
    savedCapacity = capacity;
    savedActive = active;
  }
}

class FakeOrderRepository implements OrderRepository {
  final orders = BehaviorSubject<List<RestaurantOrder>>.seeded([]);
  final items = BehaviorSubject<List<OrderItem>>.seeded([]);
  String? queriedWaiter;
  String? openedTable;
  int? savedQuantity;
  String? savedNotes;
  @override
  Stream<List<RestaurantOrder>> watchOrders({String? waiterId}) {
    queriedWaiter = waiterId;
    return orders.stream;
  }

  @override
  Stream<RestaurantOrder?> watchOrder(String id) =>
      orders.map((list) => list.where((o) => o.id == id).firstOrNull);
  @override
  Stream<List<OrderItem>> watchItems(String id) => items.stream;
  @override
  Future<String> openOrder(String tableId, String waiterId) async {
    openedTable = tableId;
    return 'order';
  }

  @override
  Future<void> addItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  ) async {
    savedQuantity = quantity;
    savedNotes = notes;
  }

  @override
  Future<void> updateItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  ) => addItem(orderId, dishId, quantity, notes);
  @override
  Future<void> removeItem(String orderId, String dishId) async {}
  @override
  Future<void> changeStatus(String id, OrderStatus status) async {}
}
