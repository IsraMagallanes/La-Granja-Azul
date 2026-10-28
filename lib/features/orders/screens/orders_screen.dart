import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/order_providers.dart';
import '../widgets/order_async_view.dart';
import '../widgets/order_detail.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(ordersProvider),
    onRetry: () => ref.invalidate(ordersProvider),
    builder: (orders) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Pedidos', style: Theme.of(context).textTheme.headlineMedium),
        if (orders.isEmpty) const Text('Aún no hay pedidos para mostrar.'),
        for (final order in orders)
          Card(
            child: ListTile(
              title: Text('Mesa ${order.tableId} · ${order.status.label}'),
              subtitle: Text(
                '${order.itemCount} productos · Responsable: ${order.waiterName}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showOrderDetail(context, order.id),
            ),
          ),
      ],
    ),
  );
}
