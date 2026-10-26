import '../../users/models/app_user.dart';
import '../models/session_state.dart';

/// Decide el estado de sesión a partir del perfil del usuario.
abstract final class SessionResolver {
  static SessionState fromProfile(AppUser? user) {
    if (user == null) return const AccessDenied(AccessDeniedReason.noProfile);
    if (!user.activo) return const AccessDenied(AccessDeniedReason.inactive);
    return Authenticated(user);
  }
}
