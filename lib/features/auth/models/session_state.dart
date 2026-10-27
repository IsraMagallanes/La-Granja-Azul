import '../../attendance/models/attendance_models.dart';
import '../../users/models/app_user.dart';

enum AccessDeniedReason {
  noProfile('Tu cuenta no tiene un perfil asignado. Contacta al administrador.'),
  inactive('Tu cuenta está desactivada. Contacta al administrador.'),
  terminalRevoked('Esta terminal fue revocada. Contacta al Superadmin.');

  const AccessDeniedReason(this.message);
  final String message;
}

sealed class SessionState {
  const SessionState();
}

class Unauthenticated extends SessionState {
  const Unauthenticated();
}

class Authenticated extends SessionState {
  const Authenticated(this.user);
  final AppUser user;
}

/// Perfil activo, pero el correo aún no fue verificado: sin acceso al
/// dashboard hasta verificarlo.
class EmailUnverified extends SessionState {
  const EmailUnverified(this.user);
  final AppUser user;
}

/// Sesión de una terminal de asistencia autorizada (no es personal).
class TerminalAuthenticated extends SessionState {
  const TerminalAuthenticated(this.terminal);
  final AttendanceTerminal terminal;
}

/// Hay sesión de Firebase pero el perfil no permite acceder.
class AccessDenied extends SessionState {
  const AccessDenied(this.reason);
  final AccessDeniedReason reason;
}
