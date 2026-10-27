import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../models/dish.dart';
import '../models/menu_category.dart';
import 'menu_repository.dart';

class FirestoreMenuRepository implements MenuRepository {
  FirestoreMenuRepository(this._firestore);
  final FirebaseFirestore _firestore;
  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection(FirestorePaths.categorias);
  CollectionReference<Map<String, dynamic>> get _dishes =>
      _firestore.collection(FirestorePaths.carta);
  @override
  Stream<List<MenuCategory>> watchCategories() => _watch(_categories).map(
    (snapshot) =>
        snapshot.docs.map((d) => MenuCategory.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
  );
  @override
  Stream<List<Dish>> watchDishes() => _watch(_dishes).map(
    (snapshot) =>
        snapshot.docs.map((d) => Dish.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
  );
  // El repositorio aporta el contexto de la operación; las pantallas siguen
  // recibiendo errores de dominio y no conocen excepciones de Firebase.
  Stream<QuerySnapshot<Map<String, dynamic>>> _watch(
    CollectionReference<Map<String, dynamic>> collection,
  ) => collection.snapshots().handleError((Object error, StackTrace stack) {
    final failure = ErrorMapper.map(error);
    if (failure.code != 'permission-denied') {
      Error.throwWithStackTrace(failure, stack);
    }
    Error.throwWithStackTrace(
      AppFailure(
        'No se pudo cargar la carta: Firestore denegó la lectura de '
        '“${collection.path}”. Contacta al administrador para revisar las reglas publicadas.',
        code: failure.code,
      ),
      stack,
    );
  });

  Future<void> _save(
    CollectionReference<Map<String, dynamic>> collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      await (id.isEmpty ? collection.doc() : collection.doc(id)).set(data);
    } catch (error, stack) {
      final failure = ErrorMapper.map(error);
      if (failure.code != 'permission-denied') {
        Error.throwWithStackTrace(failure, stack);
      }
      Error.throwWithStackTrace(
        AppFailure(
          'Firestore denegó guardar en “${collection.path}”. '
          'Se requiere un perfil admin o superadmin activo, datos válidos '
          'y las reglas de la carta publicadas.',
          code: failure.code,
        ),
        stack,
      );
    }
  }

  @override
  Future<void> saveCategory(MenuCategory category) =>
      _save(_categories, category.id, category.toMap());
  @override
  Future<void> saveDish(Dish dish) => _save(_dishes, dish.id, dish.toMap());
}
