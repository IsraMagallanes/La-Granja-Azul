import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class MenuAdminScreen extends StatelessWidget {
  const MenuAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Administración de la carta',
      icon: Icons.menu_book,
      description: 'Edición de platos y categorías (próximamente).',
    );
  }
}
