import '../models/order_item.dart';
import '../models/restaurant_order.dart';

abstract interface class OrderRepository {
  Stream<List<RestaurantOrder>> watchOrders({String? waiterId});
  Stream<RestaurantOrder?> watchOrder(String id);
  Stream<List<OrderItem>> watchItems(String orderId);
  Future<String> openOrder(String tableId, String waiterId);
  Future<void> addItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  );
  Future<void> updateItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  );
  Future<void> removeItem(String orderId, String dishId);
  Future<void> changeStatus(String orderId, OrderStatus status);
}
