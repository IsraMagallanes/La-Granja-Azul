class OrderItem {
  const OrderItem({
    required this.dishId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.notes,
  });
  final String dishId;
  final String name;
  final double price;
  final int quantity;
  final String notes;
  int get unitCents => (price * 100).round();
  int get subtotalCents => unitCents * quantity;
  factory OrderItem.fromMap(String id, Map<String, dynamic> d) => OrderItem(
    dishId: id,
    name: d['nombre'] as String,
    price: (d['precio'] as num).toDouble(),
    quantity: d['cantidad'] as int,
    notes: d['observaciones'] as String,
  );
}

String soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';
int orderTotal(Iterable<OrderItem> items) =>
    items.fold(0, (total, item) => total + item.subtotalCents);
