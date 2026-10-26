/// Validadores de formularios reutilizables. Devuelven `null` si es válido.
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, {String field = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) return '$field es obligatorio.';
    return null;
  }

  static String? email(String? value) {
    final empty = required(value, field: 'El correo');
    if (empty != null) return empty;
    if (!_email.hasMatch(value!.trim())) return 'Ingresa un correo válido.';
    return null;
  }

  static String? password(String? value) {
    final empty = required(value, field: 'La contraseña');
    if (empty != null) return empty;
    if (value!.length < 6) return 'Mínimo 6 caracteres.';
    return null;
  }
}
