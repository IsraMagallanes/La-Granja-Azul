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

  // --- Datos de personal. Las mismas expresiones viven en firestore.rules;
  // mantenerlas alineadas.
  static final _dni = RegExp(r'^\d{8}$');
  static final _carnetExtranjeria = RegExp(r'^[A-Z0-9]{9,12}$');
  static final _celular = RegExp(r'^9\d{8}$');
  static final _persona =
      RegExp(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .'-]*$");

  static String? dni(String? value) {
    final empty = required(value, field: 'El DNI');
    if (empty != null) return empty;
    return _dni.hasMatch(value!.trim()) ? null : 'El DNI debe tener 8 dígitos.';
  }

  /// Carné de extranjería: 9 a 12 caracteres alfanuméricos.
  static String? carnetExtranjeria(String? value) {
    final empty = required(value, field: 'El carné de extranjería');
    if (empty != null) return empty;
    return _carnetExtranjeria.hasMatch(value!.trim().toUpperCase())
        ? null
        : 'El carné debe tener entre 9 y 12 letras o números.';
  }

  /// Celular peruano sin prefijo: 9 dígitos que empiezan con 9 (+51).
  static String? celular(String? value) {
    final empty = required(value, field: 'El celular');
    if (empty != null) return empty;
    return _celular.hasMatch(value!.trim())
        ? null
        : 'El celular debe tener 9 dígitos y empezar con 9.';
  }

  static String? celularOpcional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return celular(value);
  }

  static String? persona(String? value, {String field = 'El nombre'}) {
    final empty = required(value, field: field);
    if (empty != null) return empty;
    final text = value!.trim();
    if (text.length < 2 || text.length > 60 || !_persona.hasMatch(text)) {
      return '$field no es válido.';
    }
    return null;
  }

  static String? motivo(String? value, {int min = 10}) {
    final empty = required(value, field: 'El motivo');
    if (empty != null) return empty;
    return value!.trim().length >= min
        ? null
        : 'Describe el motivo (mínimo $min caracteres).';
  }
}
