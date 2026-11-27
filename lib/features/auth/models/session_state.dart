import '../../users/models/app_user.dart';

enum AccessDeniedReason {
  noProfile(
    'Tu cuenta no tiene un perfil asignado. Contacta al administrador.',
  ),
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
  const Authenticated(this.user, {this.onShift = true});
  final AppUser user;

  /// Jornada abierta (entrada registrada y sin salida). Los módulos operativos
  /// la exigen salvo a Superadmin y Admin; la fija `sessionProvider` y, si
  /// falta el dato, queda cerrada para los roles que la requieren.
  final bool onShift;
}

/// Perfil activo, pero el correo aún no fue verificado: sin acceso al
/// dashboard hasta verificarlo.
class EmailUnverified extends SessionState {
  const EmailUnverified(this.user);
  final AppUser user;
}

/// Hay sesión de Firebase pero el perfil no permite acceder.
class AccessDenied extends SessionState {
  const AccessDenied(this.reason);
  final AccessDeniedReason reason;
}
