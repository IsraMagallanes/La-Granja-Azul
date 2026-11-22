import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/dish.dart';
import '../models/menu_category.dart';
import '../repositories/dish_photo_repository.dart';
import '../repositories/menu_repository.dart';
import '../services/dish_photo_picker.dart';
import '../services/menu_service.dart';

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => throw UnimplementedError('menuRepositoryProvider sin override'),
);
final menuServiceProvider = Provider<MenuService>(
  (ref) => MenuService(ref.watch(menuRepositoryProvider)),
);

/// Sin fotos por defecto; `main.dart` lo reemplaza con Firestore.
final dishPhotoRepositoryProvider = Provider<DishPhotoRepository>(
  (ref) => const NoDishPhotoRepository(),
);
final dishPhotoPickerProvider = Provider<DishPhotoPicker>(
  (ref) => ImagePickerDishPhotoPicker(),
);

/// Foto de un plato, pedida solo cuando se muestra y conservada mientras la
/// app siga abierta (la carta pública no vuelve a descargarla al desplazarse).
/// Si falla, el plato se ve con su URL o con el marcador, nunca con un error.
final dishPhotoProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  id,
) async {
  try {
    return await ref.watch(dishPhotoRepositoryProvider).fetch(id);
  } catch (_) {
    return null;
  }
});

class MenuCatalog {
  const MenuCatalog(this.categories, this.dishes);
  final List<MenuCategory> categories;
  final List<Dish> dishes;
  List<Dish> dishesFor(String categoryId) =>
      dishes.where((d) => d.categoryId == categoryId).toList();
}

final menuCatalogProvider = StreamProvider.autoDispose<MenuCatalog>((ref) {
  final repository = ref.watch(menuRepositoryProvider);
  return Rx.combineLatest2(
    repository.watchCategories(),
    repository.watchDishes(),
    MenuCatalog.new,
  );
}, retry: (_, _) => null);
