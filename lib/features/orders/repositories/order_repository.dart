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

  /// Registra el pedido (único cambio de estado sin motivo).
  Future<void> changeStatus(String orderId, OrderStatus status);

  /// Avanza un pedido registrado en cocina al estado siguiente ([to]).
  ///
  /// [forceReason]: solo Admin/Superadmin al pasar a «Listo» con stock
  /// insuficiente; descuenta lo disponible y deja una excepción auditada.
  Future<void> advanceKitchen(
    String orderId,
    KitchenStatus to,
    String actorUid, {
    String? forceReason,
  });

  /// Cancela el pedido y libera la mesa; guarda el motivo y quién canceló.
  Future<void> cancelOrder(String orderId, String reason, String actorUid);
}
