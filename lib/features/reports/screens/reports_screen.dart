import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Reportes',
      icon: Icons.bar_chart,
      description: 'Ventas y estadísticas (próximamente).',
    );
  }
}
