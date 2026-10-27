import '../../../core/async/request_guard.dart';
import '../repositories/auth_repository.dart';

/// Resultado legible de pedir un correo de Firebase.
class EmailOutcome {
  const EmailOutcome(this.ok, this.message);

  /// `true` solo si Firebase aceptó la solicitud (la API respondió sin error).
  final bool ok;
  final String message;
}

/// Pide los correos oficiales de Firebase (enlace de contraseña y verificación)
/// con tiempo máximo, sin solicitudes duplicadas y con mensajes que no afirman
/// más de lo confirmado.
///
/// Con la protección de enumeración de correos activa, Firebase responde igual
/// exista o no la cuenta; por eso «ok» significa «solicitud aceptada», no
/// «correo entregado».
class EmailRequester {
  EmailRequester(this._auth, this._guard);

  final AuthRepository _auth;
  final RequestGuard _guard;

  Future<EmailOutcome> sendPasswordReset(String email) async {
    final normalized = email.trim().toLowerCase();
    final outcome = await _guard.run(
        'reset:$normalized', () => _auth.sendPasswordReset(normalized));
    return _describe(
      outcome,
      accepted: 'Firebase aceptó la solicitud. Si el correo está registrado, '
          'el enlace llegará en unos minutos (revisa también spam).',
    );
  }

  Future<EmailOutcome> sendVerification() async {
    final outcome =
        await _guard.run('verify', () => _auth.sendEmailVerification());
    return _describe(
      outcome,
      accepted: 'Firebase aceptó el envío de la verificación. '
          'Revisa tu correo (y spam) en unos minutos.',
    );
  }

  EmailOutcome _describe(GuardOutcome outcome, {required String accepted}) =>
      switch (outcome) {
        GuardDone() => EmailOutcome(true, accepted),
        GuardBusy() => const EmailOutcome(
            false, 'Ya hay una solicitud en curso. Espera su resultado.'),
        GuardCoolingDown(:final left) => EmailOutcome(
            false,
            'Ya se solicitó hace poco. Podrás reintentar en '
            '${left.inSeconds + 1} s.'),
        GuardFailed(:final failure) => EmailOutcome(false, failure.message),
      };
}
