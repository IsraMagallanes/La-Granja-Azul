import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'motion.dart';

/// Pantalla de acceso de la referencia: encabezado azul marino con el
/// logotipo y una tarjeta blanca que lo solapa, centrada y de ancho acotado.
class CenteredCard extends StatelessWidget {
  const CenteredCard({super.key, required this.child, this.maxWidth = 420});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: BrandBackdrop(
            height: 280,
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 32, 28, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: BrandWordmark(size: 30),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 170, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Reveal(
                  child: Card(
                    elevation: 3,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
