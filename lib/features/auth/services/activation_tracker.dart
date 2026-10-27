import '../../users/repositories/user_repository.dart';
import '../models/session_state.dart';

/// Registra la activación de una cuenta: la primera vez que el trabajador
/// entra con el correo verificado (lo que prueba que definió su contraseña).
/// Hasta entonces el administrador ve «Pendiente de activación»; haber enviado
/// el correo no cuenta como cuenta activada.
class ActivationTracker {
  ActivationTracker(this._users);

  final UserRepository _users;
  final _attempted = <String>{};

  Future<void> onSession(SessionState? session) async {
    if (session is! Authenticated) return;
    final user = session.user;
    if (user.activadoEn != null || !_attempted.add(user.uid)) return;
    try {
      await _users.markActivated(user.uid);
    } catch (_) {
      // Se reintentará en la próxima sesión; no bloquea el acceso.
      _attempted.remove(user.uid);
    }
  }
}
