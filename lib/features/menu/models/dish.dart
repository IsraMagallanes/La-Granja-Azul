class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.price,
    required this.imageUrl,
    this.available = true,
  });
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final double price;
  final String imageUrl;
  final bool available;
  Dish copyWith({bool? available}) => Dish(
    id: id,
    name: name,
    description: description,
    categoryId: categoryId,
    price: price,
    imageUrl: imageUrl,
    available: available ?? this.available,
  );
  factory Dish.fromMap(String id, Map<String, dynamic> data) => Dish(
    id: id,
    name: data['nombre'] as String,
    description: data['descripcion'] as String,
    categoryId: data['categoriaId'] as String,
    price: (data['precio'] as num).toDouble(),
    imageUrl: data['imagenUrl'] as String,
    available: data['disponible'] as bool,
  );
  Map<String, dynamic> toMap() => {
    'nombre': name,
    'descripcion': description,
    'categoriaId': categoryId,
    'precio': price,
    'imagenUrl': imageUrl,
    'disponible': available,
  };
}
