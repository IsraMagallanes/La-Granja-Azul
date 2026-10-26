import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/widgets/module_placeholder.dart';

/// Carta digital pública: solo lectura, sin login, carrito ni pagos.
class PublicMenuScreen extends StatelessWidget {
  const PublicMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: const ModulePlaceholder(
        title: 'Nuestra carta',
        icon: Icons.restaurant_menu,
        description: 'La carta digital estará disponible próximamente.',
      ),
    );
  }
}
