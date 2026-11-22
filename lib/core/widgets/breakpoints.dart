import 'package:flutter/widgets.dart';

/// Celular < 600 · tablet 600–1099 · escritorio ≥ 1100 (ancho en dp).
abstract final class Breakpoints {
  static const double medium = 600;
  static const double wide = 840;
  static const double desktop = 1100;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  /// Barra lateral fija (compacta en tablet, extendida en escritorio).
  static bool usesRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}
