import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Mesas',
      icon: Icons.table_restaurant,
      description: 'Estado y distribución de mesas (próximamente).',
    );
  }
}
