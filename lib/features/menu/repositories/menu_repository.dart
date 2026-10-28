import '../models/dish.dart';
import '../models/menu_category.dart';

abstract interface class MenuRepository {
  Stream<List<MenuCategory>> watchCategories();
  Stream<List<Dish>> watchDishes();
  Future<void> saveCategory(MenuCategory category);
  Future<void> saveDish(Dish dish);
}
