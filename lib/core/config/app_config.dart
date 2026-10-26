import 'package:flutter/foundation.dart';

/// Configuración global de la aplicación.
abstract final class AppConfig {
  static const appName = 'La Granja Azul';

  /// En web la aplicación solo expone la carta digital pública al visitante
  /// anónimo; en móvil el visitante anónimo va directo al login del personal.
  static const publicEntryIsMenu = kIsWeb;
}
