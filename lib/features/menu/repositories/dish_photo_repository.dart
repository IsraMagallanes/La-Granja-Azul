import 'dart:typed_data';

/// Fotografías de los platos (`cartaFotos/{platoId}`).
///
/// El proyecto está en el plan Spark, donde Firebase Storage no está
/// disponible sin Blaze: la foto, ya comprimida a unos pocos KB, se guarda como
/// bytes en Firestore. La carta (`carta/{id}`) no la carga, así que su lista
/// sigue siendo liviana y cada foto se pide solo cuando se muestra.
abstract interface class DishPhotoRepository {
  /// Foto JPEG del plato, o `null` si no tiene.
  Future<Uint8List?> fetch(String dishId);

  Future<void> save(String dishId, Uint8List jpeg);

  Future<void> remove(String dishId);
}

/// Sin fotos (valor por defecto); `main.dart` lo reemplaza con Firestore.
class NoDishPhotoRepository implements DishPhotoRepository {
  const NoDishPhotoRepository();

  @override
  Future<Uint8List?> fetch(String dishId) async => null;

  @override
  Future<void> save(String dishId, Uint8List jpeg) =>
      throw UnsupportedError('Repositorio de fotos no configurado.');

  @override
  Future<void> remove(String dishId) =>
      throw UnsupportedError('Repositorio de fotos no configurado.');
}
