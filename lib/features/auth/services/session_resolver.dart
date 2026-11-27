import '../../users/models/app_user.dart';
import '../models/session_state.dart';

/// Decide el estado de sesión a partir del perfil del usuario.
abstract final class SessionResolver {
  /// Acceso al dashboard: perfil existente, `activo = true` y correo
  /// verificado. Un perfil inactivo se rechaza antes que uno sin verificar.
  /// [onShift] es la jornada abierta del trabajador (ver `Authenticated`).
  static SessionState fromProfile(
    AppUser? user, {
    bool emailVerified = true,
    bool onShift = true,
  }) {
    if (user == null) return const AccessDenied(AccessDeniedReason.noProfile);
    if (!user.activo) return const AccessDenied(AccessDeniedReason.inactive);
    if (!emailVerified) return EmailUnverified(user);
    return Authenticated(user, onShift: onShift);
  }
}
