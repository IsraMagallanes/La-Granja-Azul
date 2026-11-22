import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/error/app_failure.dart';

/// Reduce una foto a un JPEG que cabe en Firestore (`cartaFotos`, ≤ 100 KB en
/// las reglas). Prueba lados y calidades decrecientes hasta que cabe.
abstract final class DishPhotoCompressor {
  /// Tope de las reglas de Firestore; mantener alineado con `firestore.rules`.
  static const rulesLimitBytes = 100000;

  /// Objetivo con holgura bajo el tope de las reglas.
  static const targetBytes = 90000;

  static const _sides = [800, 640, 480, 360];
  static const _qualities = [80, 65, 50, 40];

  static Uint8List fit(Uint8List original, {int maxBytes = targetBytes}) {
    final decoded = _decode(original);
    for (final side in _sides) {
      final scaled = decoded.width <= side && decoded.height <= side
          ? decoded
          : img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? side : null,
              height: decoded.height > decoded.width ? side : null,
              interpolation: img.Interpolation.average,
            );
      for (final quality in _qualities) {
        final jpeg = Uint8List.fromList(
          img.encodeJpg(scaled, quality: quality),
        );
        if (jpeg.length <= maxBytes) return jpeg;
      }
    }
    throw const AppFailure(
      'No se pudo reducir la foto lo suficiente. Elige otra más simple.',
    );
  }

  static img.Image _decode(Uint8List bytes) {
    final image = bytes.isEmpty ? null : img.decodeImage(bytes);
    if (image == null) {
      throw const AppFailure(
        'No se pudo leer la imagen. Usa una foto JPG, PNG o WebP.',
      );
    }
    // Aplica la orientación EXIF y descarta la transparencia: JPEG no la admite.
    return img.bakeOrientation(image).convert(numChannels: 3);
  }
}
