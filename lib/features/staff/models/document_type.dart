import '../../../core/validators/validators.dart';

/// Documento de identidad aceptado para el personal.
enum DocumentType {
  dni('dni', 'DNI'),
  ce('ce', 'Carné de extranjería');

  const DocumentType(this.value, this.label);

  final String value;
  final String label;

  static DocumentType? tryParse(Object? raw) {
    for (final type in values) {
      if (type.value == raw) return type;
    }
    return null;
  }

  /// Número en su forma canónica (sin espacios; CE en mayúsculas).
  String normalize(String raw) {
    final text = raw.trim();
    return this == ce ? text.toUpperCase() : text;
  }

  String? validate(String? number) => switch (this) {
        dni => Validators.dni(number),
        ce => Validators.carnetExtranjeria(number),
      };
}
