import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Usuarios',
      icon: Icons.group,
      description: 'Gestión de administradores y trabajadores (próximamente).',
    );
  }
}
