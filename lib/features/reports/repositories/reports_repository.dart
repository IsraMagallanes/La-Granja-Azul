import '../../cashier/models/cash_models.dart';
import '../../inventory/models/inventory_models.dart';
import '../../orders/models/order_item.dart';

/// Lecturas puntuales (no en vivo) para los reportes: se piden al abrir o al
/// actualizar, para no gastar lecturas de Firestore en cada cambio. Solo lee;
/// no escribe nada.
abstract interface class ReportsRepository {
  /// Pagos cuyo `creadoEn` cae en [from, to).
  Future<List<Payment>> payments(DateTime from, DateTime to);

  /// Detalles de los pedidos indicados (platos, cantidades y precios).
  Future<List<OrderItem>> soldItems(List<String> orderIds);

  /// Compras recibidas en [from, to).
  Future<List<Purchase>> receivedPurchases(DateTime from, DateTime to);

  Future<List<StockMovement>> stockMovements(DateTime from, DateTime to);
}
