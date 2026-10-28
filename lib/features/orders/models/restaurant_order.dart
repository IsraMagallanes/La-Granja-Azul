import '../../users/models/app_user.dart';

enum OrderStatus {
  abierto('Abierto'),
  registrado('Registrado'),
  cancelado('Cancelado');

  const OrderStatus(this.label);
  final String label;
}

class RestaurantOrder {
  const RestaurantOrder({
    required this.id,
    required this.tableId,
    required this.waiterId,
    required this.waiterName,
    required this.status,
    required this.revision,
    required this.itemCount,
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String tableId;
  final String waiterId;
  final String waiterName;
  final OrderStatus status;
  final int revision;
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  bool get editable => status == OrderStatus.abierto;
  factory RestaurantOrder.fromMap(String id, Map<String, dynamic> d) =>
      RestaurantOrder(
        id: id,
        tableId: d['mesaId'] as String,
        waiterId: d['meseroId'] as String,
        waiterName: d['meseroNombre'] as String,
        status: OrderStatus.values.byName(d['estado'] as String),
        revision: d['revision'] as int,
        itemCount: d['cantidadDetalles'] as int,
        createdAt: toDateOrNull(d['creadoEn']),
        updatedAt: toDateOrNull(d['actualizadoEn']),
      );
}
