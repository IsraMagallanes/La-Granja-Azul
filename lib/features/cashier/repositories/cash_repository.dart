import '../models/cash_models.dart';

abstract interface class CashRepository {
  /// La caja abierta ahora, o null si no hay ninguna (documento candado).
  Stream<CashBox?> watchOpenBox();
  Stream<List<CashBox>> watchBoxes();
  Stream<List<Payment>> watchPayments({String? boxId, DateTime? since});
  Stream<List<CashMovement>> watchMovements(String boxId);

  Future<String> openBox(int initialCents, {required String actorUid});
  Future<void> addMovement(
    String boxId,
    MovementType type,
    int cents,
    String concept, {
    required String actorUid,
  });

  /// Cobra un pedido: crea el pago, lo pasa a «pagado» y libera su mesa en una
  /// sola transacción. Si algo falla no se aplica nada.
  Future<void> charge({
    required String orderId,
    required int totalCents,
    required PaymentMethod method,
    required int receivedCents,
    required String actorUid,
  });

  Future<void> closeBox(
    String boxId, {
    required int countedCents,
    required CashSummary summary,
    required String notes,
    required String actorUid,
  });
}
