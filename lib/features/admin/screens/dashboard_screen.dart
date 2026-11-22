import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/models/restaurant_order.dart';
import '../../roles/controllers/role_providers.dart';
import '../../tables/controllers/table_providers.dart';

/// Dashboard compartido por Superadmin y Admin. Los indicadores salen de los
/// pedidos y mesas reales; los de ventas y reservas aparecerán con sus módulos.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final user = session.user;
    final permissions = ref
        .watch(permissionServiceProvider)
        .permissionsOf(user.role);
    final orders = ref.watch(ordersProvider).value;
    final tables = ref.watch(tablesProvider).value;

    final today = LimaTime.dateKey(DateTime.now());
    final ordersToday = orders
        ?.where(
          (o) => o.createdAt != null && LimaTime.dateKey(o.createdAt!) == today,
        )
        .length;
    final open = orders?.where((o) => o.status == OrderStatus.abierto).length;
    final active = tables?.where((t) => t.active).toList();
    final occupied = active?.where((t) => t.occupied).length;
    final text = Theme.of(context).textTheme;

    return PageBody(
      child: ListView(
        children: [
          Text(
            'Bienvenido, ${user.nombre}',
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            '${user.role.label} · resumen general del restaurante',
            style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
              final w = (c.maxWidth - 16 * (cols - 1)) / cols;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: w,
                    child: StatCard(
                      icon: Icons.receipt_long,
                      label: 'Pedidos hoy',
                      value: '${ordersToday ?? '—'}',
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: StatCard(
                      icon: Icons.pending_actions,
                      label: 'Pedidos abiertos',
                      value: '${open ?? '—'}',
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: StatCard(
                      icon: Icons.table_restaurant,
                      label: 'Mesas ocupadas',
                      value: occupied == null
                          ? '—'
                          : '$occupied / ${active!.length}',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          PanelCard(
            title: 'Últimos pedidos',
            child: orders == null || orders.isEmpty
                ? const Text(
                    'Aún no hay pedidos para mostrar.',
                    style: TextStyle(color: AppColors.inkMuted),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Mesa')),
                        DataColumn(label: Text('Responsable')),
                        DataColumn(label: Text('Productos'), numeric: true),
                        DataColumn(label: Text('Estado')),
                      ],
                      rows: [
                        for (final o in orders.take(5))
                          DataRow(
                            cells: [
                              DataCell(Text(o.tableId)),
                              DataCell(Text(o.waiterName)),
                              DataCell(Text('${o.itemCount}')),
                              DataCell(
                                StatusPill(
                                  o.status.label,
                                  tone: orderTone(o.status),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          PanelCard(
            title: 'Permisos del rol',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in permissions) Chip(label: Text(p.name)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Color de la etiqueta de un pedido según su estado.
StatusTone orderTone(OrderStatus status) => switch (status) {
  OrderStatus.abierto => StatusTone.warning,
  OrderStatus.registrado => StatusTone.success,
  OrderStatus.pagado => StatusTone.info,
  OrderStatus.cancelado => StatusTone.danger,
};
