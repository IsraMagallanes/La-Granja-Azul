import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../models/dish.dart';
import '../models/menu_category.dart';
import '../repositories/menu_repository.dart';
import '../services/menu_service.dart';

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => throw UnimplementedError('menuRepositoryProvider sin override'),
);
final menuServiceProvider = Provider<MenuService>(
  (ref) => MenuService(ref.watch(menuRepositoryProvider)),
);

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
