import 'package:flutter/material.dart';

/// Contenedor centrado de ancho acotado para formularios y mensajes.
class CenteredCard extends StatelessWidget {
  const CenteredCard({super.key, required this.child, this.maxWidth = 420});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Card(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }
}
