import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Inventario',
      icon: Icons.inventory_2,
      description: 'Control de insumos y stock (próximamente).',
    );
  }
}
