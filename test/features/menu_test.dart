import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/menu/controllers/menu_providers.dart';
import 'package:granja_azul/features/menu/models/menu_category.dart';
import 'package:granja_azul/features/menu/models/dish.dart';
import 'package:granja_azul/features/menu/repositories/menu_repository.dart';
import 'package:granja_azul/features/menu/services/menu_service.dart';
import 'package:granja_azul/features/menu/screens/public_menu_screen.dart';
import 'package:granja_azul/features/menu/widgets/menu_editor.dart';

class FakeMenuRepository implements MenuRepository {
  final categories = StreamController<List<MenuCategory>>.broadcast();
  final dishes = StreamController<List<Dish>>.broadcast();
  MenuCategory? savedCategory;
  Dish? savedDish;
  @override
  Stream<List<MenuCategory>> watchCategories() => categories.stream;
  @override
  Stream<List<Dish>> watchDishes() => dishes.stream;
  @override
  Future<void> saveCategory(MenuCategory category) async {
    savedCategory = category;
  }

  @override
  Future<void> saveDish(Dish dish) async {
    savedDish = dish;
  }

  Future<void> close() async {
    await categories.close();
    await dishes.close();
  }
}

const category = MenuCategory(id: 'aves', name: 'Aves');
const dish = Dish(
  id: 'pollo',
  name: 'Pollo',
  description: 'A la brasa',
  categoryId: 'aves',
  price: 25.5,
  imageUrl: 'https://example.com/pollo.jpg',
);
void main() {
  test('validación de precios, obligatorios e imágenes', () {
    for (final value in ['', '0', '-1', 'NaN', 'Infinity', 'abc', '1000001']) {
      expect(MenuValidation.price(value), isNotNull);
    }
    expect(MenuValidation.price('25,50'), isNull);
    expect(MenuValidation.requiredText('  '), isNotNull);
    expect(MenuValidation.requiredText('x' * 121), isNotNull);
    expect(MenuValidation.imageUrl('data:image/png;base64,abc'), isNotNull);
    expect(MenuValidation.imageUrl('http://example.com/a.jpg'), isNotNull);
    expect(MenuValidation.imageUrl(dish.imageUrl), isNull);
  });
  test('modelos conservan datos al serializar', () {
    expect(Dish.fromMap(dish.id, dish.toMap()).toMap(), dish.toMap());
    expect(
      MenuCategory.fromMap(category.id, category.toMap()).toMap(),
      category.toMap(),
    );
  });
  test('servicio valida y conserva asociación al desactivar', () async {
    final repository = FakeMenuRepository();
    final service = MenuService(repository);
    expect(
      () => service.saveCategory(const MenuCategory(id: '', name: ' ')),
      throwsException,
    );
    await service.saveDish(dish);
    await service.saveCategory(
      const MenuCategory(id: 'aves', name: ' Aves ', active: false),
    );
    expect(repository.savedCategory!.active, false);
    expect(repository.savedCategory!.name, 'Aves');
    expect(repository.savedDish!.categoryId, 'aves');
    await repository.close();
  });
  testWidgets(
    'carta reactiva muestra precio, disponibilidad y oculta categoría inactiva',
    (tester) async {
      final repository = FakeMenuRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [menuRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: PublicMenuScreen()),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.categories.add([category]);
      repository.dishes.add([dish]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Pollo'), findsOneWidget);
      expect(find.text('S/ 25.50'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
      repository.dishes.add([
        Dish(
          id: dish.id,
          name: dish.name,
          description: dish.description,
          categoryId: dish.categoryId,
          price: 30,
          imageUrl: dish.imageUrl,
          available: false,
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('S/ 30.00'), findsOneWidget);
      expect(find.text('No disponible'), findsOneWidget);
      repository.categories.add([
        const MenuCategory(id: 'aves', name: 'Aves', active: false),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Pollo'), findsNothing);
      expect(find.text('Aún no hay categorías en la carta.'), findsOneWidget);
      repository.categories.addError(Exception('fallo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );
  testWidgets('formulario rechaza campos vacíos y guarda categoría', (
    tester,
  ) async {
    final repository = FakeMenuRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [menuRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: MenuEditor.category())),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Este campo es obligatorio.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Postres');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repository.savedCategory!.name, 'Postres');
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });
}
