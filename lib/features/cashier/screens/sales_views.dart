import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../orders/models/order_item.dart';
import '../../orders/widgets/order_async_view.dart';
import '../../orders/widgets/order_detail.dart';
import '../controllers/cash_providers.dart';
import '../models/cash_models.dart';

enum _Range {
  today('Hoy'),
  current('Caja actual'),
  all('Todas');

  const _Range(this.label);
  final String label;
}

/// Ventas cobradas, con total por método de pago.
class SalesView extends ConsumerStatefulWidget {
  const SalesView({super.key});
  @override
  ConsumerState<SalesView> createState() => _SalesViewState();
}

class _SalesViewState extends ConsumerState<SalesView> {
  _Range _range = _Range.today;

  @override
  Widget build(BuildContext context) {
    final box = ref.watch(openBoxProvider).value;
    final value = switch (_range) {
      _Range.today => ref.watch(todayPaymentsProvider),
      _Range.current =>
        box == null
            ? const AsyncData(<Payment>[])
            : ref.watch(boxPaymentsProvider(box.id)),
      _Range.all => ref.watch(allPaymentsProvider),
    };
    return OrderAsyncView(
      value: value,
      onRetry: () => ref.invalidate(todayPaymentsProvider),
      builder: (payments) {
        final summary = CashSummary.from(
          initial: 0,
          payments: payments,
          movements: const [],
        );
        return PageBody(
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Ventas',
                subtitle: 'Pedidos cobrados. Horas de Lima.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in _Range.values)
                    FilterPill(
                      label: r.label,
                      selected: r == _range,
                      onTap: () => setState(() => _range = r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 210,
                    child: StatCard(
                      icon: Icons.attach_money,
                      label: 'Total vendido',
                      value: soles(summary.totalSales),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: StatCard(
                      icon: Icons.receipt_long,
                      label: 'Ventas',
                      value: '${summary.salesCount}',
                    ),
                  ),
                  for (final m in PaymentMethod.values)
                    SizedBox(
                      width: 210,
                      child: StatCard(
                        icon: m.isCash ? Icons.payments : Icons.credit_card,
                        label: m.label,
                        value: soles(summary.byMethod[m]!),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (payments.isEmpty)
                const StateMessage(
                  icon: Icons.bar_chart,
                  title: 'No hay ventas en este periodo.',
                ),
              for (final p in payments)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt, color: AppColors.blue),
                    title: Text('Mesa ${p.tableId} · ${soles(p.total)}'),
                    subtitle: Text(
                      '${p.method.label} · ${p.byName}'
                      '${p.at == null ? '' : ' · ${LimaTime.formatDateTime(p.at!)}'}',
                    ),
                    trailing: p.method.isCash && p.change > 0
                        ? Text('Vuelto ${soles(p.change)}')
                        : null,
                    onTap: () => showOrderDetail(context, p.orderId),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Cajas abiertas y cerradas, con sus totales y diferencias.
class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(boxesProvider),
    onRetry: () => ref.invalidate(boxesProvider),
    builder: (boxes) => PageBody(
      child: ListView(
        children: [
          const SectionHeader(
            title: 'Historial de cajas',
            subtitle:
                'Las últimas 60 cajas. Las cajas cerradas no se modifican.',
          ),
          if (boxes.isEmpty)
            const StateMessage(
              icon: Icons.history,
              title: 'Aún no hay cajas registradas.',
            ),
          for (final b in boxes) _BoxCard(box: b),
        ],
      ),
    ),
  );
}

class _BoxCard extends StatelessWidget {
  const _BoxCard({required this.box});
  final CashBox box;

  @override
  Widget build(BuildContext context) {
    final diff = box.difference;
    final opened = box.openedAt == null
        ? '—'
        : LimaTime.formatDateTime(box.openedAt!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Abierta $opened por ${box.openedByName}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!box.closed)
                  const StatusPill('Abierta', tone: StatusTone.info)
                else
                  StatusPill(
                    diff == 0
                        ? 'Cuadra'
                        : diff! > 0
                        ? 'Sobran ${soles(diff)}'
                        : 'Faltan ${soles(-diff)}',
                    tone: diff == 0 ? StatusTone.success : StatusTone.danger,
                  ),
              ],
            ),
            if (box.closed) ...[
              Text(
                'Cerrada ${box.closedAt == null ? '' : LimaTime.formatDateTime(box.closedAt!)} por ${box.closedByName ?? '—'}',
                style: const TextStyle(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 6),
              Text(
                'Fondo ${soles(box.initial)} · Efectivo ${soles(box.cashSales ?? 0)} · '
                'Otros ${soles(box.otherSales ?? 0)} · Ingresos ${soles(box.income ?? 0)} · '
                'Egresos ${soles(box.expenses ?? 0)} · ${box.salesCount ?? 0} ventas',
              ),
              Text(
                'Esperado ${soles(box.expected ?? 0)} · Contado ${soles(box.counted ?? 0)}',
              ),
              if (box.closeNotes.isNotEmpty) Text('Nota: ${box.closeNotes}'),
            ],
          ],
        ),
      ),
    );
  }
}
