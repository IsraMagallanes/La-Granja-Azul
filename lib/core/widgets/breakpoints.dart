import 'package:flutter/widgets.dart';

abstract final class Breakpoints {
  static const double wide = 840;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}
