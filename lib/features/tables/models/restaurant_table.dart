class RestaurantTable {
  const RestaurantTable({
    required this.id,
    required this.capacity,
    required this.active,
    this.activeOrderId,
  });
  final String id;
  final int capacity;
  final bool active;
  final String? activeOrderId;
  bool get occupied => activeOrderId != null;
  factory RestaurantTable.fromMap(String id, Map<String, dynamic> data) =>
      RestaurantTable(
        id: id,
        capacity: data['capacidad'] as int,
        active: data['activo'] as bool,
        activeOrderId: data['pedidoActivo'] as String?,
      );
}
