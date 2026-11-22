import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../admin/screens/dashboard_screen.dart' show orderTone;
import '../controllers/order_providers.dart';
import '../widgets/order_async_view.dart';
import '../widgets/order_detail.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(ordersProvider),
    onRetry: () => ref.invalidate(ordersProvider),
    builder: (orders) => PageBody(
      child: ListView(
        children: [
          const SectionHeader(
            title: 'Pedidos',
            subtitle: 'Toca un pedido para ver su detalle.',
          ),
          if (orders.isEmpty)
            const StateMessage(
              icon: Icons.receipt_long,
              title: 'Aún no hay pedidos para mostrar.',
            ),
          for (final order in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.blueSoft,
                    child: Icon(Icons.receipt_long, color: AppColors.blue),
                  ),
                  title: Text(
                    'Mesa ${order.tableId}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${order.itemCount} productos · Responsable: ${order.waiterName}'
                    '${order.kitchen == null ? '' : ' · Cocina: ${order.kitchen!.label}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(
                        order.status.label,
                        tone: orderTone(order.status),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => showOrderDetail(context, order.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
