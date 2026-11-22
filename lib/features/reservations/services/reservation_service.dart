import '../../../core/error/app_failure.dart';
import '../../../core/time/lima_time.dart';
import '../../orders/repositories/order_repository.dart';
import '../../tables/models/restaurant_table.dart';
import '../models/reservation.dart';
import '../repositories/reservation_repository.dart';

abstract final class ReservationValidation {
  static String? customer(String? value) {
    final length = (value ?? '').trim().length;
    return length < 2 || length > 80 ? 'Nombre de 2 a 80 caracteres.' : null;
  }

  static String? phone(String? value) =>
      RegExp(r'^[0-9+ ]{7,20}$').hasMatch((value ?? '').trim())
      ? null
      : 'Teléfono de 7 a 20 dígitos (puede llevar + y espacios).';

  static String? partySize(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 1 || n > 50 ? 'Entre 1 y 50 personas.' : null;
  }

  static String? notes(String? value) =>
      (value ?? '').trim().length > 300 ? 'Máximo 300 caracteres.' : null;

  static String? cancelReason(String? value) {
    final length = (value ?? '').trim().length;
    return length < 3 || length > 200
        ? 'Indica el motivo (3 a 200 caracteres).'
        : null;
  }
}

class ReservationService {
  const ReservationService(this.repository, this.orders);
  final ReservationRepository repository;
  final OrderRepository orders;

  /// Valida el borrador contra las mesas y las demás reservas abiertas. Las
  /// reglas no pueden comparar horarios entre documentos, así que el cruce de
  /// una misma mesa se avisa aquí (la última palabra sobre mesa activa,
  /// capacidad y fecha futura la tienen las reglas).
  ReservationDraft _checked(
    ReservationDraft draft, {
    required List<RestaurantTable> tables,
    required List<Reservation> existing,
    required DateTime now,
    String? ignoreId,
  }) {
    final error =
        ReservationValidation.customer(draft.customer) ??
        ReservationValidation.phone(draft.phone) ??
        ReservationValidation.partySize('${draft.partySize}') ??
        ReservationValidation.notes(draft.notes);
    if (error != null) throw AppFailure(error);
    final table = tables.where((t) => t.id == draft.tableId).firstOrNull;
    if (table == null || !table.active) {
      throw const AppFailure('Elige una mesa activa.');
    }
    if (draft.partySize > table.capacity) {
      throw AppFailure(
        'La mesa ${table.id} es para ${table.capacity} personas como máximo.',
      );
    }
    if (!draft.at.isAfter(now)) {
      throw const AppFailure(
        'La reservación debe ser en una fecha y hora futuras.',
      );
    }
    final clash = existing
        .where(
          (r) =>
              r.id != ignoreId &&
              r.status.open &&
              r.tableId == draft.tableId &&
              r.overlaps(draft.at),
        )
        .firstOrNull;
    if (clash != null) {
      throw AppFailure(
        'La mesa ${draft.tableId} ya está reservada a las '
        '${LimaTime.formatTime(clash.at)} (cada reserva ocupa '
        '${Reservation.stay.inHours} horas).',
      );
    }
    return ReservationDraft(
      tableId: draft.tableId,
      customer: draft.customer.trim(),
      phone: draft.phone.trim(),
      partySize: draft.partySize,
      at: draft.at,
      notes: draft.notes.trim(),
    );
  }

  Future<void> create(
    ReservationDraft draft, {
    required String actorUid,
    required String actorName,
    required List<RestaurantTable> tables,
    required List<Reservation> existing,
    DateTime? now,
  }) async => repository.create(
    _checked(
      draft,
      tables: tables,
      existing: existing,
      now: now ?? DateTime.now(),
    ),
    actorUid: actorUid,
    actorName: actorName,
  );

  Future<void> edit(
    Reservation current,
    ReservationDraft draft, {
    required List<RestaurantTable> tables,
    required List<Reservation> existing,
    DateTime? now,
  }) async {
    if (!current.status.open) {
      throw const AppFailure('Esta reservación ya no admite cambios.');
    }
    return await repository.edit(
      current.id,
      _checked(
        draft,
        tables: tables,
        existing: existing,
        now: now ?? DateTime.now(),
        ignoreId: current.id,
      ),
      confirmed: current.status == ReservationStatus.confirmada,
    );
  }

  Future<void> confirm(Reservation r) async {
    if (r.status != ReservationStatus.pendiente) {
      throw const AppFailure('Solo se confirman reservaciones pendientes.');
    }
    return await repository.confirm(r.id);
  }

  Future<void> cancel(Reservation r, String reason) async {
    final error = ReservationValidation.cancelReason(reason);
    if (error != null) throw AppFailure(error);
    if (!r.status.open) {
      throw const AppFailure('Esta reservación ya no admite cambios.');
    }
    return await repository.cancel(r.id, reason.trim());
  }

  Future<void> markNoShow(Reservation r, {DateTime? now}) async {
    if (!r.status.open || (now ?? DateTime.now()).isBefore(r.at)) {
      throw const AppFailure('Solo se marca «No asistió» pasada la hora.');
    }
    return await repository.markNoShow(r.id);
  }

  /// Los clientes llegaron: abre el pedido de la mesa y deja la reserva como
  /// cumplida enlazada a él. Si la mesa está ocupada el pedido no se abre y la
  /// reserva sigue confirmada.
  Future<String> seat(Reservation r, {required String waiterUid}) async {
    if (r.status != ReservationStatus.confirmada) {
      throw const AppFailure(
        'Confirma la reservación antes de sentar a los clientes.',
      );
    }
    final orderId = await orders.openOrder(r.tableId, waiterUid);
    try {
      await repository.seat(r.id, orderId);
    } catch (_) {
      throw AppFailure(
        'Se abrió el pedido de la mesa ${r.tableId}, pero no se pudo marcar '
        'la reservación como cumplida. Revísala en Reservaciones.',
      );
    }
    return orderId;
  }
}
