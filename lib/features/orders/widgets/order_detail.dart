import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../controllers/order_providers.dart';
import '../models/order_item.dart';
import '../models/restaurant_order.dart';
import '../services/order_policy.dart';
import 'operation_button.dart';
import 'order_async_view.dart';
import 'item_editor.dart';

Future<void> showOrderDetail(BuildContext context, String id) =>
    showDialog<void>(
      context: context,
      builder: (_) => OrderDetail(orderId: id),
    );

class OrderDetail extends ConsumerWidget {
  const OrderDetail({super.key, required this.orderId});
  final String orderId;
  Future<bool> _confirm(BuildContext context, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: const Text('Detalle del pedido'),
    content: SizedBox(
      width: 700,
      child: OrderAsyncView(
        value: ref.watch(orderProvider(orderId)),
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (order) {
          if (order == null) return const Text('El pedido no existe.');
          final session = ref.watch(sessionProvider).value;
          final editable =
              session is Authenticated &&
              OrderPolicy.canEdit(session.user, order);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Mesa ${order.tableId} · ${order.status.label}'),
                SelectableText('Responsable: ${order.waiterName}'),
                Text(
                  'Creado (Lima): ${order.createdAt == null ? 'Pendiente de confirmar' : LimaTime.formatDateTime(order.createdAt!)}',
                ),
                Text(
                  'Actualizado (Lima): ${order.updatedAt == null ? 'Pendiente de confirmar' : LimaTime.formatDateTime(order.updatedAt!)}',
                ),
                if (!order.editable)
                  const Text('Este pedido ya no admite cambios.'),
                OrderAsyncView(
                  value: ref.watch(orderItemsProvider(orderId)),
                  onRetry: () => ref.invalidate(orderItemsProvider(orderId)),
                  builder: (items) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (items.isEmpty)
                        const Text('Aún no hay productos en este pedido.'),
                      for (final item in items)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.quantity} × ${item.name} · ${soles(item.unitCents)}',
                                ),
                                if (item.notes.isNotEmpty) Text(item.notes),
                                Text('Subtotal: ${soles(item.subtotalCents)}'),
                                if (editable)
                                  Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: () => showDialog<void>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => ItemEditor(
                                            orderId: orderId,
                                            item: item,
                                          ),
                                        ),
                                        child: const Text('Editar'),
                                      ),
                                      OperationButton(
                                        label: 'Retirar',
                                        onPressed: () async {
                                          if (await _confirm(
                                            context,
                                            '¿Retirar ${item.name}?',
                                          )) {
                                            await ref
                                                .read(orderServiceProvider)
                                                .remove(orderId, item.dishId);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        'Total: ${soles(orderTotal(items))}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                if (editable)
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ItemEditor(orderId: orderId),
                        ),
                        child: const Text('Añadir plato'),
                      ),
                      OperationButton(
                        label: 'Registrar pedido',
                        onPressed: order.itemCount == 0
                            ? null
                            : () async {
                                if (await _confirm(
                                  context,
                                  '¿Registrar el pedido? Ya no podrás editarlo.',
                                )) {
                                  await ref
                                      .read(orderServiceProvider)
                                      .status(orderId, OrderStatus.registrado);
                                }
                              },
                      ),
                      OperationButton(
                        label: 'Cancelar pedido',
                        onPressed: () async {
                          if (await _confirm(
                            context,
                            '¿Cancelar el pedido y liberar la mesa?',
                          )) {
                            await ref
                                .read(orderServiceProvider)
                                .status(orderId, OrderStatus.cancelado);
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
