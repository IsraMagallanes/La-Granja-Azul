import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

class WaiterScreen extends StatelessWidget {
  const WaiterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Mesero',
      icon: Icons.room_service,
      description: 'Toma de pedidos por mesa (próximamente).',
    );
  }
}
