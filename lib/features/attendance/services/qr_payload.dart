import 'dart:math';

/// Contenido del QR: solo un identificador opaco de un solo uso. No incluye
/// nombre, documento, rol ni identificador del trabajador.
abstract final class QrPayload {
  static const prefix = 'GA1:';
  static final _id = RegExp(r'^[0-9a-f]{32}$');

  static String encode(String tokenId) => '$prefix$tokenId';

  /// Devuelve el id del token o `null` si el texto escaneado no es un QR de
  /// asistencia válido.
  static String? decode(String? raw) {
    if (raw == null || !raw.startsWith(prefix)) return null;
    final id = raw.substring(prefix.length);
    return _id.hasMatch(id) ? id : null;
  }

  /// Id aleatorio de 128 bits generado con un RNG criptográfico.
  static String generateId([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
