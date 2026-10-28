import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/menu/models/menu_category.dart';
import 'package:granja_azul/features/menu/repositories/firestore_menu_repository.dart';

// Solo simulan los límites de red: verifican que el contexto no se pierda al
// propagar fallos reales de Firebase hacia las dos pantallas.
class FailingFirestore implements FirebaseFirestore {
  FailingFirestore(this.code);
  final String code;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      FailingCollection(path, code);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Doble de prueba: no se utiliza como implementación del SDK en producción.
// ignore: subtype_of_sealed_class
class FailingCollection implements CollectionReference<Map<String, dynamic>> {
  FailingCollection(this.path, this.code);
  @override
  final String path;
  final String code;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final error = FirebaseException(plugin: 'cloud_firestore', code: code);
    if (invocation.memberName == #snapshots) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.error(error);
    }
    if (invocation.memberName == #doc) return FailingDocument(error);
    return super.noSuchMethod(invocation);
  }
}

// Doble de prueba para provocar una escritura fallida sin acceder a Firebase.
// ignore: subtype_of_sealed_class
class FailingDocument implements DocumentReference<Map<String, dynamic>> {
  FailingDocument(this.error);
  final FirebaseException error;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #set) return Future<void>.error(error);
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test(
    'lecturas identifican Firestore, colección y operación sin culpar al rol',
    () async {
      final repository = FirestoreMenuRepository(
        FailingFirestore('permission-denied'),
      );
      for (final entry in {
        'categorias': repository.watchCategories(),
        'carta': repository.watchDishes(),
      }.entries) {
        await expectLater(
          entry.value,
          emitsError(
            isA<AppFailure>()
                .having((f) => f.code, 'code', 'permission-denied')
                .having(
                  (f) => f.message,
                  'contexto',
                  allOf(
                    contains('Firestore'),
                    contains('lectura'),
                    contains(entry.key),
                    isNot(contains('Se requiere un perfil')),
                  ),
                ),
          ),
        );
      }
    },
  );
  test('escritura denegada diferencia perfil, validación y reglas', () async {
    final repository = FirestoreMenuRepository(
      FailingFirestore('permission-denied'),
    );
    await expectLater(
      repository.saveCategory(const MenuCategory(id: '', name: 'Aves')),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.message,
          'contexto',
          allOf(
            contains('guardar'),
            contains('categorias'),
            contains('activo'),
            contains('datos válidos'),
          ),
        ),
      ),
    );
  });
  test('un fallo de red conserva su código y mensaje', () async {
    final repository = FirestoreMenuRepository(FailingFirestore('unavailable'));
    await expectLater(
      repository.watchCategories(),
      emitsError(
        isA<AppFailure>()
            .having((f) => f.code, 'code', 'unavailable')
            .having(
              (f) => f.message,
              'mensaje',
              'Servicio no disponible. Intenta más tarde.',
            ),
      ),
    );
  });
}
