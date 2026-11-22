import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// Color de una etiqueta de estado (Activo, Pendiente, Cancelado…).
enum StatusTone {
  success(AppColors.successBg, AppColors.successFg),
  warning(AppColors.warnBg, AppColors.warnFg),
  danger(AppColors.dangerBg, AppColors.dangerFg),
  info(AppColors.infoBg, AppColors.infoFg),
  neutral(AppColors.neutralBg, AppColors.neutralFg);

  const StatusTone(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

/// Etiqueta de estado redondeada, como las de las tablas de la referencia.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: tone.background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: tone.foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Indicador con icono en recuadro azul claro (Pedidos hoy, Mesas ocupadas…).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.blue, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                  Text(
                    value,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta blanca con título, acción opcional y contenido (tablas, gráficos).
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Píldora de filtro (Todos, Entradas…): azul intenso cuando está activa.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Interactive(
    child: Material(
      color: selected ? AppColors.blue : AppColors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.blue : AppColors.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}
