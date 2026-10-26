import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
