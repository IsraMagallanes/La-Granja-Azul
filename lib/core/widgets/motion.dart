import 'package:flutter/material.dart';

/// Efecto táctil para botones, filtros y tarjetas: crece al pasar el cursor y
/// se hunde al presionar. No intercepta toques: solo anima a su hijo.
class Interactive extends StatefulWidget {
  const Interactive({
    super.key,
    required this.child,
    this.hoverScale = 1.04,
    this.glow = false,
  });

  final Widget child;
  final double hoverScale;

  /// Añade un halo azul mientras el cursor está encima.
  final bool glow;

  @override
  State<Interactive> createState() => _InteractiveState();
}

class _InteractiveState extends State<Interactive> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final scale = _down ? 0.96 : (_hover ? widget.hoverScale : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: widget.glow
              ? AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1C5FD4)
                            .withValues(alpha: _hover ? 0.45 : 0),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: widget.child,
                )
              : widget.child,
        ),
      ),
    );
  }
}

/// Aparición escalonada (fundido + deslizamiento hacia arriba) de listas y
/// cuadrículas: el elemento `index` tarda un poco más que el anterior.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + 70 * index.clamp(0, 10)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
