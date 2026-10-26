import '../models/app_user.dart';

abstract interface class UserRepository {
  /// Emite el perfil del usuario (o `null` si no existe / es inválido) cada
  /// vez que cambia en el servidor.
  Stream<AppUser?> watchUser(String uid);
}
