import '../models/app_user.dart';

abstract interface class UserRepository {
  /// Emite el perfil del usuario (o `null` si no existe / es inválido) cada
  /// vez que cambia en el servidor.
  Stream<AppUser?> watchUser(String uid);

  /// Registra la primera entrada con el correo verificado (una sola vez; las
  /// reglas exigen `email_verified` y que no estuviera registrada).
  Future<void> markActivated(String uid);
}
