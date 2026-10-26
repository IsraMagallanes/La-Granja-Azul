/// Error de dominio con mensaje apto para mostrar al usuario.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
