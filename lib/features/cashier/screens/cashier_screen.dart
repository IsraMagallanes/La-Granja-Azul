import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/models/order_item.dart';
import '../../orders/models/restaurant_order.dart';
import '../../orders/widgets/order_async_view.dart';
import '../../orders/widgets/order_detail.dart';
import '../controllers/cash_providers.dart';
import '../widgets/charge_dialog.dart';
import 'cash_view.dart';
import 'sales_views.dart';

enum CashSection {
  charge('Cobrar', Icons.point_of_sale),
  box('Caja', Icons.account_balance_wallet),
  sales('Ventas', Icons.bar_chart),
  history('Historial', Icons.history);

  const CashSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Área de Caja. Tiene su propia navegación vertical (riel lateral; barra
/// inferior en celular) con Cobrar, Caja, Ventas e Historial. Cajeros, Admin y
/// Superadmin entran por «Caja» del panel principal.
class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key, this.initial = CashSection.charge});
  final CashSection initial;
  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  late CashSection _section = widget.initial;

  Widget _body() => switch (_section) {
    CashSection.charge => ChargeView(
      onOpenBox: () => setState(() => _section = CashSection.box),
    ),
    CashSection.box => const CashView(),
    CashSection.sales => const SalesView(),
    CashSection.history => const HistoryView(),
  };

  @override
  Widget build(BuildContext context) {
    final box = ref.watch(openBoxProvider).value;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final destinations = [for (final s in CashSection.values) s];
        if (wide) {
          return Row(
            children: [
              NavigationRail(
                backgroundColor: Colors.white,
                selectedIndex: destinations.indexOf(_section),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: StatusPill(
                    box == null ? 'Caja cerrada' : 'Caja abierta',
                    tone: box == null ? StatusTone.neutral : StatusTone.success,
                  ),
                ),
                onDestinationSelected: (i) =>
                    setState(() => _section = destinations[i]),
                destinations: [
                  for (final s in destinations)
                    NavigationRailDestination(
                      icon: Icon(s.icon),
                      label: Text(s.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _body()),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: _body()),
            NavigationBar(
              selectedIndex: destinations.indexOf(_section),
              onDestinationSelected: (i) =>
                  setState(() => _section = destinations[i]),
              destinations: [
                for (final s in destinations)
                  NavigationDestination(icon: Icon(s.icon), label: s.label),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Pedidos entregados en mesa, listos para cobrar.
class ChargeView extends ConsumerWidget {
  const ChargeView({super.key, required this.onOpenBox});
  final VoidCallback onOpenBox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox();
    final box = ref.watch(openBoxProvider);
    return OrderAsyncView(
      value: ref.watch(ordersProvider),
      onRetry: () => ref.invalidate(ordersProvider),
      builder: (orders) {
        bool registered(RestaurantOrder o) =>
            o.status == OrderStatus.registrado;
        final ready =
            [
              for (final o in orders)
                if (registered(o) && o.kitchen == KitchenStatus.entregado) o,
            ]..sort(
              (a, b) => (a.updatedAt ?? DateTime(1970)).compareTo(
                b.updatedAt ?? DateTime(1970),
              ),
            );
        final inProgress = [
          for (final o in orders)
            if (registered(o) && o.kitchen != KitchenStatus.entregado) o,
        ];
        return PageBody(
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Cobrar',
                subtitle: 'Pedidos entregados en mesa. Al cobrar, la mesa queda libre.',
              ),
              if (box.value == null)
                Card(
                  color: AppColors.warnBg,
                  child: ListTile(
                    leading: const Icon(Icons.lock, color: AppColors.warnFg),
                    title: const Text(
                      'La caja está cerrada: ábrela para cobrar.',
                    ),
                    trailing: TextButton(
                      onPressed: onOpenBox,
                      child: const Text('Ir a Caja'),
                    ),
                  ),
                ),
              if (ready.isEmpty)
                const StateMessage(
                  icon: Icons.point_of_sale,
                  title: 'No hay pedidos entregados por cobrar.',
                ),
              for (final o in ready)
                _ChargeRow(order: o, canCharge: box.value != null),
              if (inProgress.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Aún no entregados',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final o in inProgress)
                  ListTile(
                    leading: const Icon(Icons.hourglass_bottom),
                    title: Text('Mesa ${o.tableId} · ${o.waiterName}'),
                    subtitle: Text('Cocina: ${o.kitchen?.label ?? '—'}'),
                    onTap: () => showOrderDetail(context, o.id),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChargeRow extends ConsumerWidget {
  const _ChargeRow({required this.order, required this.canCharge});
  final RestaurantOrder order;
  final bool canCharge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(orderItemsProvider(order.id)).value;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(
          backgroundColor: AppColors.blueSoft,
          child: Icon(Icons.table_restaurant, color: AppColors.blue),
        ),
        title: Text(
          'Mesa ${order.tableId}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${order.itemCount} platos · Atendió ${order.waiterName}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              items == null ? '…' : soles(orderTotal(items)),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: canCharge
                  ? () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ChargeDialog(order: order),
                    )
                  : null,
              child: const Text('Cobrar'),
            ),
          ],
        ),
        onTap: () => showOrderDetail(context, order.id),
      ),
    );
  }
}
