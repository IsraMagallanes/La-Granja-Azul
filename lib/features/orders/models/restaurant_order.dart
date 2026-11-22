import '../../users/models/app_user.dart';

enum OrderStatus {
  abierto('Abierto'),
  registrado('Registrado'),
  pagado('Pagado'),
  cancelado('Cancelado');

  const OrderStatus(this.label);
  final String label;
}

/// Avance de un pedido registrado en la cocina. Un pedido registrado antes de
/// la Fase 5 (sin el campo) cuenta como pendiente.
enum KitchenStatus {
  pendiente('Pendiente'),
  preparando('En preparación'),
  listo('Listo'),
  entregado('Entregado');

  const KitchenStatus(this.label);
  final String label;

  /// El único estado al que se puede pasar desde este (null si ya terminó).
  KitchenStatus? get next => switch (this) {
    pendiente => preparando,
    preparando => listo,
    listo => entregado,
    entregado => null,
  };
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
    this.cancelReason,
    this.kitchen,
    this.registeredAt,
    this.preparingAt,
    this.readyAt,
    this.deliveredAt,
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

  /// Motivo con el que se canceló (solo en pedidos cancelados).
  final String? cancelReason;

  /// Estado en cocina; solo existe en pedidos registrados.
  final KitchenStatus? kitchen;
  final DateTime? registeredAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? deliveredAt;
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
        cancelReason: d['motivoCancelacion'] as String?,
        kitchen: (d['estado'] == 'registrado' || d['estado'] == 'pagado')
            ? KitchenStatus.values.byName(
                (d['estadoCocina'] as String?) ?? 'pendiente',
              )
            : null,
        registeredAt: toDateOrNull(d['registradoEn']),
        preparingAt: toDateOrNull(d['preparandoEn']),
        readyAt: toDateOrNull(d['listoEn']),
        deliveredAt: toDateOrNull(d['entregadoEn']),
      );
}
