import 'package:flutter/material.dart';

import 'page_scaffold.dart';

/// Pantalla base de un módulo cuya lógica se implementará más adelante.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.icon,
    this.description = 'Módulo en preparación.',
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) =>
      StateMessage(icon: icon, title: title, message: description);
}
