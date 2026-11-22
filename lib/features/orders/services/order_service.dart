import '../../../core/error/app_failure.dart';
import '../models/restaurant_order.dart';
import '../repositories/order_repository.dart';

abstract final class OrderValidation {
  /// Motivo mínimo para forzar «Listo» con stock insuficiente (Fase 8B).
  static const forceReasonMin = 10;

  static String? quantity(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 99 ? 'Cantidad entre 1 y 99.' : null;
  }

  static String? notes(String? value) =>
      (value ?? '').trim().length > 500 ? 'Máximo 500 caracteres.' : null;

  static String? cancelReason(String? value) {
    final length = (value ?? '').trim().length;
    return length < 3 || length > 200
        ? 'Indica el motivo (3 a 200 caracteres).'
        : null;
  }
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

  /// Mueve un pedido registrado al siguiente paso de cocina. La política
  /// (quién puede) se aplica en la interfaz y, de forma definitiva, en las reglas.
  Future<void> advanceKitchen(
    RestaurantOrder order,
    KitchenStatus to,
    String actorUid, {
    String? forceReason,
  }) async {
    if (order.status != OrderStatus.registrado || order.kitchen?.next != to) {
      throw const AppFailure('Ese cambio de estado de cocina no es válido.');
    }
    if (forceReason != null) {
      if (to != KitchenStatus.listo) {
        throw const AppFailure('Solo se fuerza el paso a «Listo».');
      }
      if (forceReason.trim().length < OrderValidation.forceReasonMin ||
          forceReason.trim().length > 200) {
        throw const AppFailure('El motivo debe tener de 10 a 200 caracteres.');
      }
    }
    return await repository.advanceKitchen(
      order.id,
      to,
      actorUid,
      forceReason: forceReason?.trim(),
    );
  }

  Future<void> cancel(String id, String reason, String actorUid) {
    final error = OrderValidation.cancelReason(reason);
    if (error != null) throw AppFailure(error);
    return repository.cancelOrder(id, reason.trim(), actorUid);
  }
}
