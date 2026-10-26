import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Cocina',
      icon: Icons.soup_kitchen,
      description: 'Cola de preparación de pedidos (próximamente).',
    );
  }
}
