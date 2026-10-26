import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Pedidos',
      icon: Icons.receipt_long,
      description: 'Seguimiento de pedidos (próximamente).',
    );
  }
}
