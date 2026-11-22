import '../../../core/error/app_failure.dart';
import '../../orders/models/order_item.dart';
import '../../orders/models/restaurant_order.dart';
import '../../orders/repositories/order_repository.dart';
import '../models/cash_models.dart';
import '../repositories/cash_repository.dart';

abstract final class CashValidation {
  static const maxInitial = 10000000; // S/ 100,000.00, igual que las reglas
  static const maxMovement = 10000000;

  static String? concept(String? value) {
    final length = (value ?? '').trim().length;
    return length < 3 || length > 120
        ? 'Concepto de 3 a 120 caracteres.'
        : null;
  }

  static String? notes(String? value) =>
      (value ?? '').trim().length > 200 ? 'Máximo 200 caracteres.' : null;
}

class CashService {
  const CashService(this.repository, this.orders);
  final CashRepository repository;
  final OrderRepository orders;

  Future<String> openBox(int initialCents, {required String actorUid}) async {
    if (initialCents < 0 || initialCents > CashValidation.maxInitial) {
      throw const AppFailure('El fondo inicial no es válido.');
    }
    return repository.openBox(initialCents, actorUid: actorUid);
  }

  Future<void> addMovement(
    CashBox box,
    MovementType type,
    int cents,
    String concept, {
    required String actorUid,
  }) async {
    final error = CashValidation.concept(concept);
    if (error != null) throw AppFailure(error);
    if (cents < 1 || cents > CashValidation.maxMovement) {
      throw const AppFailure('El monto no es válido.');
    }
    return repository.addMovement(
      box.id,
      type,
      cents,
      concept.trim(),
      actorUid: actorUid,
    );
  }

  /// Total de un pedido: suma de sus detalles ya guardados (no cambian una vez
  /// registrado el pedido).
  Future<int> totalOf(RestaurantOrder order) async =>
      orderTotal(await orders.watchItems(order.id).first);

  /// Cobra un pedido entregado. El pago, el cierre del pedido y la liberación
  /// de la mesa los hace el repositorio en una sola transacción: si algo
  /// falla, la mesa sigue ocupada y no queda pago.
  Future<int> charge({
    required RestaurantOrder order,
    required CashBox? box,
    required PaymentMethod method,
    required int receivedCents,
    required String actorUid,
  }) async {
    if (box == null) throw const AppFailure('Abre la caja antes de cobrar.');
    if (order.status == OrderStatus.pagado) {
      throw const AppFailure('Este pedido ya fue cobrado.');
    }
    if (order.status != OrderStatus.registrado ||
        order.kitchen != KitchenStatus.entregado) {
      throw const AppFailure(
        'Solo se cobran pedidos registrados y ya entregados en la mesa.',
      );
    }
    final total = await totalOf(order);
    if (total <= 0) throw const AppFailure('El pedido no tiene total.');
    if (method.isCash && receivedCents < total) {
      throw const AppFailure('El efectivo recibido no alcanza para el total.');
    }
    await repository.charge(
      orderId: order.id,
      totalCents: total,
      method: method,
      receivedCents: method.isCash ? receivedCents : total,
      actorUid: actorUid,
    );
    return method.isCash ? receivedCents - total : 0;
  }

  Future<void> closeBox(
    CashBox box, {
    required int countedCents,
    required List<Payment> payments,
    required List<CashMovement> movements,
    required String notes,
    required String actorUid,
  }) async {
    if (countedCents < 0)
      throw const AppFailure('El efectivo contado no es válido.');
    final summary = CashSummary.from(
      initial: box.initial,
      payments: payments,
      movements: movements,
    );
    final difference = countedCents - summary.expectedCash;
    final error = CashValidation.notes(notes);
    if (error != null) throw AppFailure(error);
    if (difference != 0 && notes.trim().length < 3) {
      throw const AppFailure(
        'Hay diferencia entre lo contado y lo esperado: explica el motivo.',
      );
    }
    return repository.closeBox(
      box.id,
      countedCents: countedCents,
      summary: summary,
      notes: notes.trim(),
      actorUid: actorUid,
    );
  }
}
