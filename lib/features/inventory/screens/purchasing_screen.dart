import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/inventory_providers.dart';
import '../models/inventory_models.dart';
import '../widgets/inventory_dialogs.dart';

String _soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

/// Proveedores y compras. Solo Admin y Superadmin (ruta `/app/compras`).
class PurchasingScreen extends StatelessWidget {
  const PurchasingScreen({super.key});

  static const _tabs = [
    ('Compras', Icons.shopping_cart),
    ('Proveedores', Icons.local_shipping),
  ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: _tabs.length,
    child: Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in _tabs) Tab(icon: Icon(t.$2), text: t.$1)],
          ),
        ),
        const Expanded(
          child: TabBarView(children: [PurchasesTab(), SuppliersTab()]),
        ),
      ],
    ),
  );
}

class SuppliersTab extends ConsumerWidget {
  const SuppliersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(suppliersProvider),
    onRetry: () => ref.invalidate(suppliersProvider),
    builder: (list) => PageBody(
      child: ListView(
        children: [
          const SectionHeader(
            title: 'Proveedores',
            subtitle: 'No se borran: se desactivan para conservar el historial de compras.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              onPressed: () =>
                  showActionDialog(context, const SupplierDialog()),
              label: const Text('Nuevo proveedor'),
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const StateMessage(
              icon: Icons.local_shipping,
              title: 'Aún no hay proveedores.',
            ),
          for (final s in list)
            Card(
              child: ListTile(
                title: Text(
                  s.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [
                    if (s.ruc.isNotEmpty) 'RUC ${s.ruc}',
                    if (s.phone.isNotEmpty) s.phone,
                    if (s.contact.isNotEmpty) s.contact,
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!s.active)
                      const StatusPill('Inactivo', tone: StatusTone.neutral),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit),
                      onPressed: () => showActionDialog(
                        context,
                        SupplierDialog(supplier: s),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class PurchasesTab extends ConsumerWidget {
  const PurchasesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(purchasesProvider),
    onRetry: () => ref.invalidate(purchasesProvider),
    builder: (list) => PageBody(
      child: ListView(
        children: [
          const SectionHeader(
            title: 'Compras',
            subtitle: 'Al recibir una compra el stock sube y el costo de cada insumo se actualiza.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.add_shopping_cart),
              onPressed: () => showActionDialog(
                context,
                PurchaseDialog(
                  supplies: ref.read(suppliesProvider).value ?? const [],
                  suppliers: ref.read(suppliersProvider).value ?? const [],
                ),
              ),
              label: const Text('Nueva compra'),
            ),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const StateMessage(
              icon: Icons.shopping_cart,
              title: 'Aún no hay compras.',
            ),
          for (final p in list) _PurchaseCard(purchase: p),
        ],
      ),
    ),
  );
}

class _PurchaseCard extends ConsumerWidget {
  const _PurchaseCard({required this.purchase});
  final Purchase purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = purchase;
    final tone = switch (p.status) {
      PurchaseStatus.pendiente => StatusTone.warning,
      PurchaseStatus.recibida => StatusTone.success,
      PurchaseStatus.cancelada => StatusTone.danger,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.supplierName} · ${_soles(p.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                StatusPill(p.status.label, tone: tone),
              ],
            ),
            Text(
              '${p.byName}${p.at == null ? '' : ' · ${LimaTime.formatDateTime(p.at!)}'}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            for (final l in p.lines)
              Text('• ${Qty.format(l.qty)} ${l.name} × ${_soles(l.unitCost)}'),
            if (p.cancelReason != null) Text('Motivo: ${p.cancelReason}'),
            if (p.status == PurchaseStatus.pendiente)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OperationButton(
                      label: 'Recibir compra',
                      onPressed: () => ref
                          .read(inventoryServiceProvider)
                          .receivePurchase(
                            p,
                            actorUid: actorUidOf(ref),
                            isAdmin: actorIsAdminOf(ref),
                          ),
                    ),
                    OutlinedButton(
                      onPressed: () => showActionDialog(
                        context,
                        CancelPurchaseDialog(purchase: p),
                      ),
                      child: const Text('Cancelar'),
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
