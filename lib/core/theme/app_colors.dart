import 'package:flutter/material.dart';

/// Paleta tomada de la referencia `docs/referencias/diseno.jpeg`: encabezados
/// azul marino, fondos blancos, azul intenso para acciones y estados en verde,
/// amarillo y rojo suaves. Única fuente de colores de la interfaz.
abstract final class AppColors {
  // Azules de marca.
  static const navyDeep = Color(0xFF061B45);
  static const navy = Color(0xFF0A2A66);
  static const blue = Color(0xFF1C5FD4); // botones y acciones principales
  static const blueDark = Color(0xFF123F8F);
  static const blueSoft = Color(0xFFE3EDFD);
  static const blueMist = Color(0xFFF3F6FB); // fondo de pantalla
  static const accentYellow = Color(0xFFF5B82E); // punto del logotipo

  // Neutros.
  static const white = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F1F3D);
  static const inkMuted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F2);

  // Estados (fondo suave + texto oscuro, como las etiquetas de la referencia).
  static const successBg = Color(0xFFD8F2D0);
  static const successFg = Color(0xFF1E6B2B);
  static const warnBg = Color(0xFFFFF0B3);
  static const warnFg = Color(0xFF8A6500);
  static const dangerBg = Color(0xFFFBD5D5);
  static const dangerFg = Color(0xFFB42318);
  static const infoBg = Color(0xFFD9E8FF);
  static const infoFg = Color(0xFF123F8F);
  static const neutralBg = Color(0xFFE9EDF3);
  static const neutralFg = Color(0xFF475569);

  /// Degradado de encabezados: azul marino a la izquierda, más vivo a la derecha.
  static const headerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [navyDeep, navy, Color(0xFF1749B5)],
  );
}
