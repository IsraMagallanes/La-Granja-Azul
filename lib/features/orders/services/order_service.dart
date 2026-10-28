import '../../../core/error/app_failure.dart';
import '../models/restaurant_order.dart';
import '../repositories/order_repository.dart';

abstract final class OrderValidation {
  static String? quantity(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 99 ? 'Cantidad entre 1 y 99.' : null;
  }

  static String? notes(String? value) =>
      (value ?? '').trim().length > 500 ? 'Máximo 500 caracteres.' : null;
}

class OrderService {
  const OrderService(this.repository);
  final OrderRepository repository;
  void _validate(int quantity, String notes) {
    final error =
        OrderValidation.quantity('$quantity') ?? OrderValidation.notes(notes);
    if (error != null) throw AppFailure(error);
  }

  Future<String> open(String tableId, String waiterId) =>
      repository.openOrder(tableId, waiterId);
  Future<void> add(String orderId, String dishId, int quantity, String notes) {
    _validate(quantity, notes);
    return repository.addItem(orderId, dishId, quantity, notes.trim());
  }

  Future<void> update(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  ) {
    _validate(quantity, notes);
    return repository.updateItem(orderId, dishId, quantity, notes.trim());
  }

  Future<void> remove(String orderId, String dishId) =>
      repository.removeItem(orderId, dishId);
  Future<void> status(String id, OrderStatus status) =>
      repository.changeStatus(id, status);
}
