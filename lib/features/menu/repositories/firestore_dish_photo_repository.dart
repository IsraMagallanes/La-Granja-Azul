import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import 'dish_photo_repository.dart';

class FirestoreDishPhotoRepository implements DishPhotoRepository {
  FirestoreDishPhotoRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String dishId) =>
      _firestore.collection(FirestorePaths.cartaFotos).doc(dishId);

  @override
  Future<Uint8List?> fetch(String dishId) async {
    final data = (await _doc(dishId).get()).data();
    final photo = data?['foto'];
    return photo is Blob ? photo.bytes : null;
  }

  @override
  Future<void> save(String dishId, Uint8List jpeg) => _guard(
    () => _doc(dishId).set({
      'foto': Blob(jpeg),
      'tipo': 'image/jpeg',
      'actualizadoEn': FieldValue.serverTimestamp(),
    }),
    'guardar la foto',
  );

  @override
  Future<void> remove(String dishId) =>
      _guard(() => _doc(dishId).delete(), 'quitar la foto');

  Future<void> _guard(Future<void> Function() action, String what) async {
    try {
      await action();
    } catch (error, stack) {
      final failure = ErrorMapper.map(error);
      Error.throwWithStackTrace(
        failure.code == 'permission-denied'
            ? AppFailure(
                'Firestore denegó $what. Se requiere un perfil admin o '
                'superadmin activo, una foto de hasta 100 KB y las reglas '
                'publicadas.',
                code: failure.code,
              )
            : failure,
        stack,
      );
    }
  }
}
