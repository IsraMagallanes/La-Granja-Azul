import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/menu/controllers/menu_providers.dart';
import 'package:granja_azul/features/menu/models/dish.dart';
import 'package:granja_azul/features/menu/models/menu_category.dart';
import 'package:granja_azul/features/menu/repositories/dish_photo_repository.dart';
import 'package:granja_azul/features/menu/repositories/menu_repository.dart';
import 'package:granja_azul/features/menu/screens/menu_admin_screen.dart';
import 'package:granja_azul/features/menu/screens/public_menu_screen.dart';
import 'package:granja_azul/features/menu/services/dish_photo_compressor.dart';
import 'package:granja_azul/features/menu/services/dish_photo_picker.dart';
import 'package:granja_azul/features/menu/services/menu_service.dart';
import 'package:granja_azul/features/menu/widgets/menu_editor.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:image/image.dart' as img;

import '../support/fakes.dart';

/// PNG con ruido: no se comprime bien, así que obliga a reducirlo de verdad.
Uint8List noisyPng(int width, int height) {
  final random = Random(7);
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _MenuRepo implements MenuRepository {
  final categories = StreamController<List<MenuCategory>>.broadcast();
  final dishes = StreamController<List<Dish>>.broadcast();
  final saved = <Dish>[];

  @override
  Stream<List<MenuCategory>> watchCategories() => categories.stream;
  @override
  Stream<List<Dish>> watchDishes() => dishes.stream;
  @override
  Future<void> saveCategory(MenuCategory category) async {}
  @override
  Future<void> saveDish(Dish dish) async => saved.add(dish);
}

class _PhotoRepo implements DishPhotoRepository {
  final store = <String, Uint8List>{};
  final removed = <String>[];
  Object? failSave;

  @override
  Future<Uint8List?> fetch(String dishId) async => store[dishId];
  @override
  Future<void> save(String dishId, Uint8List jpeg) async {
    if (failSave != null) throw failSave!;
    store[dishId] = jpeg;
  }

  @override
  Future<void> remove(String dishId) async {
    removed.add(dishId);
    store.remove(dishId);
  }
}

class _Picker implements DishPhotoPicker {
  _Picker(this.next);
  Uint8List? next;
  @override
  Future<Uint8List?> pick() async => next;
}

const _aves = MenuCategory(id: 'aves', name: 'Aves');
const _pollo = Dish(
  id: 'pollo',
  name: 'Pollo',
  description: 'A la brasa con papas y ensalada',
  categoryId: 'aves',
  price: 25.5,
  imageUrl: '',
);

void main() {
  group('reducción de la foto', () {
    test(
      'una foto grande y con ruido queda en JPEG bajo el tope de las reglas',
      () {
        final jpeg = DishPhotoCompressor.fit(noisyPng(1600, 1200));
        expect(jpeg.length, lessThanOrEqualTo(DishPhotoCompressor.targetBytes));
        expect(
          DishPhotoCompressor.targetBytes,
          lessThan(DishPhotoCompressor.rulesLimitBytes),
        );
        expect(jpeg.sublist(0, 2), [0xFF, 0xD8]); // cabecera JPEG
        final decoded = img.decodeJpg(jpeg)!;
        expect(decoded.width, lessThanOrEqualTo(800));
        expect(decoded.height, lessThanOrEqualTo(800));
      },
    );

    test('conserva la proporción y reduce también las fotos verticales', () {
      final decoded = img.decodeJpg(
        DishPhotoCompressor.fit(noisyPng(600, 1200)),
      )!;
      expect(decoded.height, greaterThan(decoded.width));
      expect(decoded.height, lessThanOrEqualTo(800));
    });

    test('una imagen pequeña no se agranda', () {
      final decoded = img.decodeJpg(DishPhotoCompressor.fit(noisyPng(64, 48)))!;
      expect(decoded.width, 64);
      expect(decoded.height, 48);
    });

    test(
      'un archivo que no es imagen o está vacío se rechaza con un mensaje',
      () {
        for (final bytes in [
          Uint8List(0),
          Uint8List.fromList([1, 2, 3, 4]),
        ]) {
          expect(
            () => DishPhotoCompressor.fit(bytes),
            throwsA(isA<AppFailure>()),
          );
        }
      },
    );

    test('si no cabe ni al mínimo, falla en vez de superar el tope', () {
      expect(
        () => DishPhotoCompressor.fit(noisyPng(400, 400), maxBytes: 500),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  test('la URL de imagen es opcional pero, si existe, debe ser HTTPS', () {
    expect(MenuValidation.optionalImageUrl(''), isNull);
    expect(MenuValidation.optionalImageUrl('   '), isNull);
    expect(
      MenuValidation.optionalImageUrl('https://example.com/a.jpg'),
      isNull,
    );
    expect(
      MenuValidation.optionalImageUrl('http://example.com/a.jpg'),
      isNotNull,
    );
    expect(
      MenuValidation.optionalImageUrl('data:image/png;base64,abc'),
      isNotNull,
    );
  });

  test('los platos nuevos reciben un id propio y distinto', () {
    final ids = {for (var i = 0; i < 50; i++) MenuService.newDishId()};
    expect(ids, hasLength(50));
    expect(
      ids.every((id) => RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id)),
      isTrue,
    );
  });

  group('editor de platos', () {
    late _MenuRepo menu;
    late _PhotoRepo photos;
    late _Picker picker;

    Future<void> pumpEditor(WidgetTester tester, {Dish? dish}) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            menuRepositoryProvider.overrideWithValue(menu),
            dishPhotoRepositoryProvider.overrideWithValue(photos),
            dishPhotoPickerProvider.overrideWithValue(picker),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MenuEditor.dish(dish: dish, categories: const [_aves]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      menu = _MenuRepo();
      photos = _PhotoRepo();
      picker = _Picker(noisyPng(320, 240));
    });

    testWidgets(
      'plato nuevo solo con foto: guarda el plato con su id y la foto reducida',
      (tester) async {
        await pumpEditor(tester);
        await tester.enterText(find.byType(TextFormField).at(0), 'Ceviche');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'Pescado fresco',
        );
        await tester.enterText(find.byType(TextFormField).at(2), '32.50');
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Aves').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Elegir foto'));
        await tester.pumpAndSettle();
        expect(find.text('Cambiar foto'), findsOneWidget);
        expect(find.text('Quitar foto'), findsOneWidget);

        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        final dish = menu.saved.single;
        expect(dish.imageUrl, isEmpty); // la URL es opcional
        expect(dish.id, hasLength(20));
        final jpeg = photos.store[dish.id]!; // la foto usa el id del plato
        expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
        expect(
          jpeg.length,
          lessThanOrEqualTo(DishPhotoCompressor.rulesLimitBytes),
        );
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'si el servidor rechaza la foto, el plato queda guardado y se explica',
      (tester) async {
        photos.failSave = const AppFailure('Firestore denegó guardar la foto.');
        await pumpEditor(tester, dish: _pollo);
        await tester.tap(find.text('Elegir foto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        expect(menu.saved, hasLength(1));
        expect(find.text('Firestore denegó guardar la foto.'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget); // sigue abierto
        expect(photos.store, isEmpty);

        // Reintentar guarda la foto sin duplicar nada.
        photos.failSave = null;
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(photos.store.keys, ['pollo']);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('quitar la foto de un plato la elimina al guardar', (
      tester,
    ) async {
      photos.store['pollo'] = Uint8List.fromList([0xFF, 0xD8, 1, 2]);
      await pumpEditor(tester, dish: _pollo);
      expect(find.text('Quitar foto'), findsOneWidget);
      await tester.tap(find.text('Quitar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Quitar foto'), findsNothing);
      expect(find.text('Elegir foto'), findsOneWidget);
      // Todavía no se borró: solo al guardar.
      expect(photos.removed, isEmpty);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(photos.removed, ['pollo']);
    });

    testWidgets(
      'un archivo que no es imagen muestra el error y no cambia la foto',
      (tester) async {
        picker.next = Uint8List.fromList([1, 2, 3]);
        await pumpEditor(tester);
        await tester.tap(find.text('Elegir foto'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('No se pudo leer la imagen'),
          findsOneWidget,
        );
        expect(find.text('Elegir foto'), findsOneWidget);
      },
    );

    testWidgets('cancelar el selector no cambia nada', (tester) async {
      picker.next = null;
      await pumpEditor(tester);
      await tester.tap(find.text('Elegir foto'));
      await tester.pumpAndSettle();
      expect(find.text('Elegir foto'), findsOneWidget);
      expect(find.textContaining('No se pudo'), findsNothing);
    });

    testWidgets('una URL que no es HTTPS sigue rechazándose', (tester) async {
      await pumpEditor(tester);
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'http://x.com/a.jpg',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.textContaining('URL HTTPS'), findsWidgets);
      expect(menu.saved, isEmpty);
    });
  });

  group('administración', () {
    testWidgets(
      'cambiar la disponibilidad desde la lista guarda el plato al instante',
      (tester) async {
        final menu = _MenuRepo();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              menuRepositoryProvider.overrideWithValue(menu),
              sessionProvider.overrideWith(
                (ref) => Stream.value(
                  Authenticated(buildUser(role: UserRole.admin)),
                ),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: MenuAdminScreen())),
          ),
        );
        await tester.pump(); // la sesión se resuelve y se suscribe a la carta
        await tester.pump();
        menu.categories.add([_aves]);
        menu.dishes.add([_pollo]);
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byType(Switch));
        await tester.pump();
        expect(menu.saved.single.id, 'pollo');
        expect(menu.saved.single.available, isFalse);
        expect(menu.saved.single.name, 'Pollo'); // el resto no cambia
      },
    );
  });

  group('carta pública', () {
    late _MenuRepo menu;
    late _PhotoRepo photos;

    Future<void> pumpMenu(
      WidgetTester tester,
      List<Dish> dishes, {
      Map<String, Uint8List> stored = const {},
    }) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      menu = _MenuRepo();
      photos = _PhotoRepo()..store.addAll(stored);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            menuRepositoryProvider.overrideWithValue(menu),
            dishPhotoRepositoryProvider.overrideWithValue(photos),
          ],
          child: const MaterialApp(home: PublicMenuScreen()),
        ),
      );
      menu.categories.add([_aves]);
      menu.dishes.add(dishes);
      await tester.pumpAndSettle();
    }

    final storedPhoto = find.byWidgetPredicate(
      (w) => w is Image && w.image is MemoryImage,
    );

    testWidgets(
      'los platos agotados van al final de su categoría y se marcan',
      (tester) async {
        const agotado = Dish(
          id: 'a',
          name: 'Anticucho',
          description: 'Corazón',
          categoryId: 'aves',
          price: 18,
          imageUrl: '',
          available: false,
        );
        await pumpMenu(tester, [agotado, _pollo]);
        expect(find.text('No disponible'), findsOneWidget);
        // «Anticucho» va antes por orden alfabético, pero está agotado: queda último.
        expect(
          tester.getTopLeft(find.text('Pollo')).dy,
          lessThan(tester.getTopLeft(find.text('Anticucho')).dy),
        );
      },
    );

    testWidgets(
      'la ficha del plato muestra la descripción completa y se cierra',
      (tester) async {
        await pumpMenu(tester, [_pollo]);
        await tester.tap(find.text('Pollo'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('A la brasa con papas y ensalada'), findsWidgets);
        expect(find.text('S/ 25.50'), findsWidgets);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('muestra la foto guardada del plato y, sin ella, el marcador', (
      tester,
    ) async {
      await pumpMenu(tester, [_pollo]);
      expect(storedPhoto, findsNothing);
      expect(find.byIcon(Icons.restaurant), findsWidgets); // marcador

      await tester.pumpWidget(const SizedBox());
      await pumpMenu(
        tester,
        [_pollo],
        stored: {'pollo': DishPhotoCompressor.fit(noisyPng(64, 48))},
      );
      expect(storedPhoto, findsOneWidget);
    });
  });
}
