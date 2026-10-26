import '../../users/models/app_user.dart';

enum AccessDeniedReason {
  noProfile('Tu cuenta no tiene un perfil asignado. Contacta al administrador.'),
  inactive('Tu cuenta está desactivada. Contacta al administrador.');

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

/// Hay sesión de Firebase pero el perfil no permite acceder.
class AccessDenied extends SessionState {
  const AccessDenied(this.reason);
  final AccessDeniedReason reason;
}
