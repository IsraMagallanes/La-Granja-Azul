class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    this.active = true,
  });
  final String id;
  final String name;
  final bool active;
  factory MenuCategory.fromMap(String id, Map<String, dynamic> data) =>
      MenuCategory(
        id: id,
        name: data['nombre'] as String,
        active: data['activo'] as bool,
      );
  Map<String, dynamic> toMap() => {'nombre': name, 'activo': active};
}
