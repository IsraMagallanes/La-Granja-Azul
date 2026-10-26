import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Roles y permisos',
      icon: Icons.admin_panel_settings,
      description: 'Matriz de roles y permisos (próximamente).',
    );
  }
}
