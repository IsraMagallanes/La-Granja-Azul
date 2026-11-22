import '../models/reservation.dart';

abstract interface class ReservationRepository {
  Stream<List<Reservation>> watchReservations();
  Future<void> create(
    ReservationDraft draft, {
    required String actorUid,
    required String actorName,
  });

  /// Edita los datos; [confirmed] conserva el estado confirmada.
  Future<void> edit(
    String id,
    ReservationDraft draft, {
    required bool confirmed,
  });
  Future<void> confirm(String id);
  Future<void> cancel(String id, String reason);
  Future<void> markNoShow(String id);

  /// Marca la reserva como cumplida enlazándola al pedido abierto.
  Future<void> seat(String id, String orderId);
}
