import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class CashierScreen extends StatelessWidget {
  const CashierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Caja',
      icon: Icons.point_of_sale,
      description: 'Cobros y cierre de cuentas (próximamente).',
    );
  }
}
