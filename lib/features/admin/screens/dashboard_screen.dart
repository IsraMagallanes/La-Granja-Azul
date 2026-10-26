import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/controllers/role_providers.dart';

/// Dashboard compartido por Superadmin y Admin; el contenido depende de los
/// permisos del rol.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final user = session.user;
    final permissions =
        ref.watch(permissionServiceProvider).permissionsOf(user.role);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Bienvenido, ${user.nombre}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(user.role.label),
        const SizedBox(height: 24),
        Text('Permisos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in permissions) Chip(label: Text(p.name)),
          ],
        ),
      ],
    );
  }
}
