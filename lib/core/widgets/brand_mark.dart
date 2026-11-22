import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_colors.dart';

/// Logotipo tipográfico de la referencia: «LA GRANJA AZUL» apilado, en blanco,
/// con el punto amarillo y la leyenda RESTAURANTE. Aparece con un fundido.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 22});

  /// Tamaño de letra de «GRANJA»; el resto se escala a partir de él.
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppColors.white,
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 0.95,
      letterSpacing: size * 0.04,
    );
    return Semantics(
      label: AppConfig.appName,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(-20 * (1 - v), 0),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LA', style: style),
                  SizedBox(width: size * 0.25),
                  Container(
                    margin: EdgeInsets.only(top: size * 0.12),
                    width: size * 0.34,
                    height: size * 0.34,
                    decoration: const BoxDecoration(
                      color: AppColors.accentYellow,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppColors.accentYellow, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
              Text('GRANJA', style: style),
              Text('AZUL', style: style),
              Text(
                'RESTAURANTE',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: size * 0.3,
                  letterSpacing: size * 0.16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encabezado azul marino con el plato de la marca (`assets/images/plato.png`,
/// recorte sin fondo). El plato entra deslizándose y creciendo, y luego flota
/// suavemente sobre un resplandor azul; se difumina hacia el azul marino por
/// la izquierda y por abajo, como en la referencia. Respeta la preferencia del
/// sistema de reducir animaciones.
class BrandBackdrop extends StatefulWidget {
  const BrandBackdrop({
    super.key,
    this.child,
    this.height,
    this.showPlate = true,
  });

  final Widget? child;
  final double? height;
  final bool showPlate;

  @override
  State<BrandBackdrop> createState() => _BrandBackdropState();
}

class _BrandBackdropState extends State<BrandBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
      return;
    }
    _enter.forward();
    // Flotación acotada (unos minutos): la pantalla termina por quedar quieta
    // y no consume animación indefinidamente.
    _float.repeat(reverse: true, count: 24);
  }

  @override
  void dispose() {
    _enter.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: widget.height,
    width: double.infinity,
    decoration: const BoxDecoration(gradient: AppColors.headerGradient),
    child: Stack(
      fit: StackFit.passthrough,
      children: [if (widget.showPlate) ..._plateLayers(), ?widget.child],
    ),
  );

  List<Widget> _plateLayers() => [
    Positioned.fill(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, c) => AnimatedBuilder(
            animation: Listenable.merge([_enter, _float]),
            builder: (context, _) {
              final e = Curves.easeOutCubic.transform(_enter.value);
              final f = Curves.easeInOut.transform(_float.value);
              return Stack(
                children: [
                  // Resplandor azul que respira detrás del plato.
                  Positioned(
                    right: -c.maxWidth * 0.1,
                    top: -c.maxHeight * 0.2,
                    bottom: -c.maxHeight * 0.2,
                    width: c.maxWidth * 0.8,
                    child: Opacity(
                      opacity: e * (0.55 + 0.35 * f),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [Color(0xFF3F86F5), Color(0x003F86F5)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -c.maxWidth * 0.12,
                    top: c.maxHeight * 0.02,
                    bottom: -c.maxHeight * 0.14,
                    child: Opacity(
                      opacity: e,
                      child: Transform.translate(
                        offset: Offset(c.maxWidth * 0.25 * (1 - e), -7 * f),
                        child: Transform.rotate(
                          angle: (f - 0.5) * 2 * math.pi / 180 * 1.6,
                          child: Transform.scale(
                            scale: 0.85 + 0.15 * e,
                            alignment: Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: c.maxWidth * 0.9,
                              ),
                              child: Image.asset(
                                'assets/images/plato.png',
                                fit: BoxFit.contain,
                                alignment: Alignment.centerRight,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.navyDeep, AppColors.navyDeep, Color(0x00061B45)],
            stops: [0, 0.3, 0.8],
          ),
        ),
      ),
    ),
    const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00061B45), Color(0x99061B45)],
            stops: [0.6, 1],
          ),
        ),
      ),
    ),
  ];
}
