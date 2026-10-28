import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/services/order_policy.dart';
import '../../orders/widgets/order_detail.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/table_providers.dart';
import '../widgets/table_editor.dart';

class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) {
      return const Center(child: Text('Inicia sesión para consultar mesas.'));
    }
    final admin = OrderPolicy.admin(session.user);
    final canOpen = OrderPolicy.canOpen(session.user);
    return OrderAsyncView(
      value: ref.watch(tablesProvider),
      onRetry: () => ref.invalidate(tablesProvider),
      builder: (tables) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Mesas', style: Theme.of(context).textTheme.headlineMedium),
          if (admin)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nueva mesa'),
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const TableEditor(),
                ),
              ),
            ),
          if (tables.isEmpty) const Text('Aún no hay mesas registradas.'),
          for (final table in tables)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesa ${table.id} · ${table.capacity} personas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      !table.active
                          ? 'Inactiva'
                          : table.occupied
                          ? 'Ocupada'
                          : 'Libre',
                    ),
                    Wrap(
                      children: [
                        if (admin)
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => TableEditor(table: table),
                            ),
                            child: const Text('Editar mesa'),
                          ),
                        if (canOpen && table.active && !table.occupied)
                          OperationButton(
                            label: 'Abrir pedido',
                            onPressed: () async {
                              final id = await ref
                                  .read(orderServiceProvider)
                                  .open(table.id, session.user.uid);
                              if (context.mounted) {
                                await showOrderDetail(context, id);
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
