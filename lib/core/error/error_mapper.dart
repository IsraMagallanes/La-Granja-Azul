import 'app_failure.dart';

/// Convierte cualquier excepción en un [AppFailure] legible.
abstract final class ErrorMapper {
  static const _generic = 'Ocurrió un error inesperado. Intenta nuevamente.';

  static const _authMessages = <String, String>{
    'invalid-email': 'El correo electrónico no es válido.',
    'user-disabled': 'Esta cuenta ha sido deshabilitada.',
    'user-not-found': 'Correo o contraseña incorrectos.',
    'wrong-password': 'Correo o contraseña incorrectos.',
    'invalid-credential': 'Correo o contraseña incorrectos.',
    'too-many-requests': 'Demasiados intentos. Espera unos minutos.',
    'network-request-failed': 'Sin conexión. Revisa tu red e intenta de nuevo.',
    'permission-denied': 'No tienes permisos para realizar esta acción.',
    'unavailable': 'Servicio no disponible. Intenta más tarde.',
  };

  static AppFailure map(Object error) {
    if (error is AppFailure) return error;
    // FirebaseException y FirebaseAuthException exponen `code`; se lee por
    // duck-typing para no acoplar el núcleo a Firebase.
    final dynamic dynamicError = error;
    try {
      final code = dynamicError.code;
      if (code is String) {
        return AppFailure(_authMessages[code] ?? _generic, code: code);
      }
    } on NoSuchMethodError {
      // No es una excepción con código.
    }
    return const AppFailure(_generic);
  }
}
