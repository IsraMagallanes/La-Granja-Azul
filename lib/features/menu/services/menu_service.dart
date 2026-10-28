import '../../../core/error/app_failure.dart';
import '../models/dish.dart';
import '../models/menu_category.dart';
import '../repositories/menu_repository.dart';

abstract final class MenuValidation {
  static String? requiredText(String? value, {int max = 120}) =>
      value == null || value.trim().isEmpty
      ? 'Este campo es obligatorio.'
      : value.trim().length > max
      ? 'Máximo $max caracteres.'
      : null;
  static double? parsePrice(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));
  static String? price(String? value) {
    final number = parsePrice(value ?? '');
    return number == null || !number.isFinite || number <= 0 || number > 1000000
        ? 'Ingresa un precio mayor que cero y hasta S/ 1000000.'
        : null;
  }

  static String? imageUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    return uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            value!.trim().length > 2048
        ? 'Ingresa una URL HTTPS de imagen (máximo 2048 caracteres).'
        : null;
  }
}

class MenuService {
  const MenuService(this._repository);
  final MenuRepository _repository;
  Future<void> saveCategory(MenuCategory category) {
    final error = MenuValidation.requiredText(category.name);
    if (error != null) throw AppFailure(error);
    return _repository.saveCategory(
      MenuCategory(
        id: category.id,
        name: category.name.trim(),
        active: category.active,
      ),
    );
  }

  Future<void> saveDish(Dish dish) {
    final error =
        MenuValidation.requiredText(dish.name) ??
        MenuValidation.requiredText(dish.description, max: 2000) ??
        MenuValidation.requiredText(dish.categoryId, max: 1500) ??
        MenuValidation.price(dish.price.toString()) ??
        MenuValidation.imageUrl(dish.imageUrl);
    if (error != null) throw AppFailure(error);
    return _repository.saveDish(
      Dish(
        id: dish.id,
        name: dish.name.trim(),
        description: dish.description.trim(),
        categoryId: dish.categoryId,
        price: dish.price,
        imageUrl: dish.imageUrl.trim(),
        available: dish.available,
      ),
    );
  }
}
