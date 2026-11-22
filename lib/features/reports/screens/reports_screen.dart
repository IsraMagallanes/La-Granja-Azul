import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../cashier/models/cash_models.dart';
import '../../inventory/models/inventory_models.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/report_providers.dart';
import '../models/report_models.dart';

String _soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

/// Reportes y estadísticas de Admin y Superadmin: ventas, platos, asistencia
/// e inventario, por periodo (días de Lima). Solo lectura.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.today;

  static const _tabs = [
    ('Ventas', Icons.attach_money),
    ('Platos', Icons.restaurant_menu),
    ('Asistencia', Icons.access_time),
    ('Inventario', Icons.inventory_2),
  ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: _tabs.length,
    child: Column(
      children: [
        Material(
          color: Colors.white,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final t in _tabs) Tab(icon: Icon(t.$2), text: t.$1),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in ReportPeriod.values)
                        FilterPill(
                          label: p.label,
                          selected: p == _period,
                          onTap: () => setState(() => _period = p),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              SalesTab(period: _period),
              DishesTab(period: _period),
              AttendanceTab(period: _period),
              InventoryTab(period: _period),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _stat(IconData icon, String label, String value) => SizedBox(
  width: 210,
  child: StatCard(icon: icon, label: label, value: value),
);

/// Barra horizontal proporcional a [fraction] (0–1).
Widget _bar(double fraction, {Color color = AppColors.blue}) => ClipRRect(
  borderRadius: BorderRadius.circular(4),
  child: LinearProgressIndicator(
    value: fraction.clamp(0, 1).toDouble(),
    minHeight: 8,
    color: color,
    backgroundColor: AppColors.blueSoft,
  ),
);

class _RefreshHeader extends StatelessWidget {
  const _RefreshHeader({
    required this.title,
    required this.subtitle,
    this.onRefresh,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SectionHeader(title: title, subtitle: subtitle),
      ),
      if (onRefresh != null)
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: onRefresh,
        ),
    ],
  );
}

class SalesTab extends ConsumerWidget {
  const SalesTab({super.key, required this.period});
  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(salesReportProvider(period)),
    onRetry: () => ref.invalidate(salesReportProvider(period)),
    builder: (r) {
      final maxDay = r.byDay.fold(0, (a, d) => d.total > a ? d.total : a);
      return PageBody(
        child: ListView(
          children: [
            _RefreshHeader(
              title: 'Ventas · ${period.label}',
              subtitle: 'Pedidos cobrados en Caja. Horas de Lima.',
              onRefresh: () => ref.invalidate(salesReportProvider(period)),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat(Icons.attach_money, 'Total vendido', _soles(r.total)),
                _stat(Icons.receipt_long, 'Ventas', '${r.count}'),
                _stat(Icons.trending_up, 'Ticket promedio', _soles(r.average)),
                _stat(
                  Icons.schedule,
                  'Hora pico',
                  r.peakHour == null
                      ? '—'
                      : '${r.peakHour.toString().padLeft(2, '0')}:00',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (r.count == 0)
              const StateMessage(
                icon: Icons.bar_chart,
                title: 'No hay ventas en este periodo.',
              )
            else ...[
              PanelCard(
                title: 'Por método de pago',
                child: Column(
                  children: [
                    for (final m in PaymentMethod.values)
                      _line(
                        m.label,
                        _soles(r.byMethod[m]!),
                        r.total == 0 ? 0 : r.byMethod[m]! / r.total,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PanelCard(
                title: 'Por día',
                child: Column(
                  children: [
                    for (final d in r.byDay)
                      _line(
                        d.dateKey,
                        '${_soles(d.total)} · ${d.count}',
                        maxDay == 0 ? 0 : d.total / maxDay,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PanelCard(
                title: 'Por cajero',
                child: Column(
                  children: [
                    for (final c in r.byCashier)
                      _line(
                        c.name,
                        '${_soles(c.total)} · ${c.count}',
                        r.total == 0 ? 0 : c.total / r.total,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _line(String label, String value, double fraction) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 3),
      _bar(fraction),
    ],
  ),
);

class DishesTab extends ConsumerStatefulWidget {
  const DishesTab({super.key, required this.period});
  final ReportPeriod period;
  @override
  ConsumerState<DishesTab> createState() => _DishesTabState();
}

class _DishesTabState extends ConsumerState<DishesTab> {
  ReportPeriod? _requested;

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final header = SectionHeader(
      title: 'Platos · ${period.label}',
      subtitle:
          'Lo más vendido, con costo y margen estimados según las recetas. '
          'Lee los detalles de cada pedido (hasta $maxDishOrders).',
    );
    if (_requested != period) {
      return PageBody(
        child: ListView(
          children: [
            header,
            FilledButton.icon(
              icon: const Icon(Icons.analytics),
              onPressed: () => setState(() => _requested = period),
              label: const Text('Analizar platos vendidos'),
            ),
          ],
        ),
      );
    }
    return OrderAsyncView(
      value: ref.watch(dishReportProvider(period)),
      onRetry: () => ref.invalidate(dishReportProvider(period)),
      builder: (r) => PageBody(
        child: ListView(
          children: [
            _RefreshHeader(
              title: 'Platos · ${period.label}',
              subtitle: 'Costo y margen estimados con el costo vigente de los insumos.',
              onRefresh: () => ref.invalidate(dishReportProvider(period)),
            ),
            if (r.truncated)
              const Card(
                color: AppColors.warnBg,
                child: ListTile(
                  leading: Icon(Icons.info, color: AppColors.warnFg),
                  title: Text(
                    'Solo se analizaron los $maxDishOrders pedidos más recientes del periodo.',
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat(Icons.restaurant_menu, 'Platos vendidos', '${r.units}'),
                _stat(Icons.attach_money, 'Ingreso', _soles(r.revenue)),
                _stat(Icons.receipt_long, 'Pedidos', '${r.orders}'),
                _stat(
                  Icons.trending_up,
                  'Margen estimado',
                  r.coveredRevenue == 0
                      ? '—'
                      : _soles(r.coveredRevenue - r.coveredCost),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (r.withoutRecipe > 0 && r.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${r.withoutRecipe} plato(s) sin receta: no entran al margen.',
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ),
            if (r.rows.isEmpty)
              const StateMessage(
                icon: Icons.restaurant_menu,
                title: 'No hay platos vendidos en este periodo.',
              ),
            for (final (i, d) in r.rows.indexed)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.blueSoft,
                    child: Text('${i + 1}'),
                  ),
                  title: Text(
                    d.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    d.cost == null
                        ? 'Ingreso ${_soles(d.revenue)} · sin receta'
                        : 'Ingreso ${_soles(d.revenue)} · costo ${_soles(d.cost!)} · margen ${_soles(d.margin!)}',
                  ),
                  trailing: Text(
                    '× ${d.quantity}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AttendanceTab extends ConsumerWidget {
  const AttendanceTab({super.key, required this.period});
  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(attendanceSummaryProvider(period)),
    onRetry: () => ref.invalidate(attendanceSummaryProvider(period)),
    builder: (r) => PageBody(
      child: ListView(
        children: [
          SectionHeader(
            title: 'Asistencia · ${period.label}',
            subtitle: 'Jornadas y horas por persona. Solo informa; no calcula pagos ni sanciones.',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(Icons.people, 'Personas', '${r.workers.length}'),
              _stat(Icons.event_available, 'Jornadas', '${r.shifts}'),
              _stat(
                Icons.schedule,
                'Horas',
                (r.minutes / 60).toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (r.workers.isEmpty)
            const StateMessage(
              icon: Icons.access_time,
              title: 'No hay asistencias en este periodo.',
            ),
          for (final w in r.workers)
            Card(
              child: ListTile(
                title: Text(
                  w.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${w.shifts} jornadas'
                  '${w.open > 0 ? ' · ${w.open} abierta(s)' : ''}'
                  '${w.regularized > 0 ? ' · ${w.regularized} regularizada(s)' : ''}',
                ),
                trailing: Text(
                  '${w.hours.toStringAsFixed(1)} h',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class InventoryTab extends ConsumerWidget {
  const InventoryTab({super.key, required this.period});
  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(inventoryReportProvider(period)),
    onRetry: () => ref.invalidate(inventoryReportProvider(period)),
    builder: (r) => PageBody(
      child: ListView(
        children: [
          _RefreshHeader(
            title: 'Inventario y costos · ${period.label}',
            subtitle: 'Valor del stock actual, compras recibidas y mermas del periodo.',
            onRefresh: () => ref.invalidate(inventoryReportProvider(period)),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(Icons.inventory_2, 'Valor del stock', _soles(r.valuation)),
              _stat(
                Icons.shopping_cart,
                'Compras recibidas',
                _soles(r.purchased),
              ),
              _stat(Icons.local_shipping, 'N.º de compras', '${r.purchases}'),
              _stat(
                Icons.delete_outline,
                'Mermas (costo)',
                _soles(r.wasteCost),
              ),
              _stat(Icons.warning_amber, 'Stock bajo', '${r.low.length}'),
              _stat(Icons.remove_shopping_cart, 'Agotados', '${r.out}'),
            ],
          ),
          const SizedBox(height: 12),
          PanelCard(
            title: 'Movimientos del periodo',
            child: Column(
              children: [
                for (final k in MovementKind.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(k.label)),
                        Text(
                          '${r.movementsByKind[k]}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PanelCard(
            title: 'Insumos con stock bajo',
            child: r.low.isEmpty
                ? const Text('Ninguno.')
                : Column(
                    children: [
                      for (final s in r.low)
                        ListTile(
                          dense: true,
                          title: Text(s.name),
                          subtitle: Text(
                            'Mínimo ${Qty.format(s.minStock)} ${s.unit.label}',
                          ),
                          trailing: Text(
                            s.stockLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: s.isOut ? AppColors.dangerFg : null,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Generado ${LimaTime.formatDateTime(DateTime.now())} (hora de Lima). '
              'El valor y el costo de mermas usan el costo vigente de cada insumo.',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    ),
  );
}
