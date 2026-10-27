import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/widgets/centered_card.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_providers.dart';
import '../models/session_state.dart';
import '../services/email_requester.dart';

/// El perfil está activo pero el correo aún no fue verificado: no se permite
/// el acceso al dashboard hasta confirmarlo.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = done);
    } catch (e) {
      if (mounted) setState(() => _message = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Correos de Firebase: el mensaje refleja el resultado real, no un «enviado»
  /// supuesto, y el guardián evita solicitudes repetidas.
  Future<void> _request(Future<EmailOutcome> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final requester = ref.read(emailRequesterProvider);
    final session = ref.watch(sessionProvider).value;
    final email = session is EmailUnverified ? session.user.email : '';
    final auth = ref.read(authRepositoryProvider);
    return Scaffold(
      body: CenteredCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_unread_outlined, size: 48),
            const SizedBox(height: 16),
            Text('Verifica tu correo',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Para entrar necesitas verificar $email. Abre el enlace que te '
              'enviamos (revisa también spam) y luego pulsa «Ya verifiqué».',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(auth.reloadAccount,
                      'Aún no aparece verificado. Abre el enlace del correo.'),
              child: const Text('Ya verifiqué'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _request(requester.sendVerification),
              child: const Text('Reenviar correo de verificación'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _request(() => requester.sendPasswordReset(email)),
              child: const Text('Reenviar enlace de contraseña'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, textAlign: TextAlign.center),
              ),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
