import '../../users/models/app_user.dart';

enum ReservationStatus {
  pendiente('Pendiente'),
  confirmada('Confirmada'),
  cumplida('Cumplida'),
  cancelada('Cancelada'),
  noAsistio('No asistió');

  const ReservationStatus(this.label);
  final String label;

  /// Aún puede cambiar (editarse, confirmarse, sentarse o cancelarse).
  bool get open => this == pendiente || this == confirmada;
}

/// Datos que el personal captura al reservar o editar.
class ReservationDraft {
  const ReservationDraft({
    required this.tableId,
    required this.customer,
    required this.phone,
    required this.partySize,
    required this.at,
    this.notes = '',
  });
  final String tableId;
  final String customer;
  final String phone;
  final int partySize;
  final DateTime at;
  final String notes;
}

class Reservation {
  const Reservation({
    required this.id,
    required this.tableId,
    required this.customer,
    required this.phone,
    required this.partySize,
    required this.at,
    required this.status,
    required this.notes,
    required this.createdByName,
    this.orderId,
    this.cancelReason,
  });

  /// Tiempo que una reserva ocupa la mesa; dos reservas de la misma mesa no
  /// pueden empezar con menos de esta separación.
  static const stay = Duration(hours: 2);

  final String id;
  final String tableId;
  final String customer;
  final String phone;
  final int partySize;
  final DateTime at;
  final ReservationStatus status;
  final String notes;
  final String createdByName;

  /// Pedido abierto al sentar a los clientes (solo en `cumplida`).
  final String? orderId;
  final String? cancelReason;

  bool overlaps(DateTime other) =>
      other.isAfter(at.subtract(stay)) && other.isBefore(at.add(stay));

  factory Reservation.fromMap(String id, Map<String, dynamic> d) => Reservation(
    id: id,
    tableId: d['mesaId'] as String,
    customer: d['cliente'] as String,
    phone: d['telefono'] as String,
    partySize: d['personas'] as int,
    at: toDateOrNull(d['fechaHora']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    status: ReservationStatus.values.byName(d['estado'] as String),
    notes: (d['notas'] as String?) ?? '',
    createdByName: (d['creadoPorNombre'] as String?) ?? '',
    orderId: d['pedidoId'] as String?,
    cancelReason: d['motivoCancelacion'] as String?,
  );
}
