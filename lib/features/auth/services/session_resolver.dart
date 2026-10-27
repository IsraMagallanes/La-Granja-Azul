import '../../attendance/models/attendance_models.dart';
import '../../users/models/app_user.dart';
import '../models/session_state.dart';

/// Decide el estado de sesión a partir del perfil del usuario.
abstract final class SessionResolver {
  /// Acceso al dashboard: perfil existente, `activo = true` y correo
  /// verificado. Un perfil inactivo se rechaza antes que uno sin verificar.
  static SessionState fromProfile(AppUser? user, {bool emailVerified = true}) {
    if (user == null) return const AccessDenied(AccessDeniedReason.noProfile);
    if (!user.activo) return const AccessDenied(AccessDeniedReason.inactive);
    if (!emailVerified) return EmailUnverified(user);
    return Authenticated(user);
  }

  /// Una cuenta sin perfil de personal puede ser una terminal autorizada
  /// (las terminales son cuentas de dispositivo, sin verificación de correo).
  static SessionState fromAccount(
    AppUser? user,
    AttendanceTerminal? terminal, {
    bool emailVerified = true,
  }) {
    if (user != null) return fromProfile(user, emailVerified: emailVerified);
    if (terminal == null) return fromProfile(null);
    if (!terminal.activo) {
      return const AccessDenied(AccessDeniedReason.terminalRevoked);
    }
    return TerminalAuthenticated(terminal);
  }
}
