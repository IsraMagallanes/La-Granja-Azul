import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/centered_card.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_providers.dart';
import '../models/session_state.dart';

class AccessDeniedScreen extends ConsumerWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final message = session is AccessDenied
        ? session.reason.message
        : 'No tienes acceso a esta sección.';
    return Scaffold(
      body: CenteredCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
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
