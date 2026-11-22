import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../menu/controllers/menu_providers.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/inventory_providers.dart';
import '../models/inventory_models.dart';
import '../widgets/inventory_dialogs.dart';

String _soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

/// Inventario: insumos y stock, movimientos, recetas y costos, proveedores y
/// compras. Lo usan Almacén, Admin y Superadmin.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  static const _tabs = [
    ('Insumos', Icons.inventory_2),
    ('Movimientos', Icons.swap_vert),
    ('Recetas', Icons.menu_book),
    ('Proveedores', Icons.local_shipping),
    ('Compras', Icons.shopping_cart),
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
          child: TabBarView(
            children: [
              SuppliesTab(),
              MovementsTab(),
              RecipesTab(),
              SuppliersTab(),
              PurchasesTab(),
            ],
          ),
        ),
      ],
    ),
  );
}

class SuppliesTab extends ConsumerStatefulWidget {
  const SuppliesTab({super.key});
  @override
  ConsumerState<SuppliesTab> createState() => _SuppliesTabState();
}

class _SuppliesTabState extends ConsumerState<SuppliesTab> {
  bool _onlyLow = false;

  @override
  Widget build(BuildContext context) => OrderAsyncView(
    value: ref.watch(suppliesProvider),
    onRetry: () => ref.invalidate(suppliesProvider),
    builder: (all) {
      final low = all.where((s) => s.isLow).length;
      final shown = _onlyLow ? all.where((s) => s.isLow).toList() : all;
      return PageBody(
        child: ListView(
          children: [
            const SectionHeader(
              title: 'Insumos',
              subtitle: 'Stock actual. El stock solo cambia con un movimiento.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: () =>
                      showActionDialog(context, const SupplyDialog()),
                  label: const Text('Nuevo insumo'),
                ),
                FilterPill(
                  label: 'Todos (${all.length})',
                  selected: !_onlyLow,
                  onTap: () => setState(() => _onlyLow = false),
                ),
                FilterPill(
                  label: 'Stock bajo ($low)',
                  selected: _onlyLow,
                  onTap: () => setState(() => _onlyLow = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const StateMessage(
                icon: Icons.inventory_2,
                title: 'No hay insumos para mostrar.',
              ),
            for (final s in shown) _SupplyCard(supply: s),
          ],
        ),
      );
    },
  );
}

class _SupplyCard extends StatelessWidget {
  const _SupplyCard({required this.supply});
  final Supply supply;

  @override
  Widget build(BuildContext context) => Card(
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
                  supply.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              if (!supply.active)
                const StatusPill('Inactivo', tone: StatusTone.neutral)
              else if (supply.isOut)
                const StatusPill('Agotado', tone: StatusTone.danger)
              else if (supply.isLow)
                const StatusPill('Stock bajo', tone: StatusTone.warning),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    showActionDialog(context, SupplyDialog(supply: supply)),
              ),
            ],
          ),
          Text(
            '${supply.stockLabel} · mínimo ${Qty.format(supply.minStock)} ${supply.unit.label} · '
            '${_soles(supply.unitCost)} por ${supply.unit.label}',
            style: const TextStyle(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final k in [
                MovementKind.entrada,
                MovementKind.salida,
                MovementKind.merma,
                MovementKind.ajuste,
              ])
                OutlinedButton(
                  onPressed: supply.active
                      ? () => showActionDialog(
                          context,
                          StockMoveDialog(supply: supply, kind: k),
                        )
                      : null,
                  child: Text(k.label),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class MovementsTab extends ConsumerWidget {
  const MovementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(stockMovementsProvider),
    onRetry: () => ref.invalidate(stockMovementsProvider),
    builder: (moves) => PageBody(
      child: ListView(
        children: [
          const SectionHeader(
            title: 'Movimientos',
            subtitle: 'Los últimos 100. Son de solo lectura: no se editan ni se borran.',
          ),
          if (moves.isEmpty)
            const StateMessage(
              icon: Icons.swap_vert,
              title: 'Aún no hay movimientos.',
            ),
          for (final m in moves)
            Card(
              child: ListTile(
                leading: Icon(
                  m.delta > 0 ? Icons.south_west : Icons.north_east,
                  color: m.delta > 0 ? AppColors.successFg : AppColors.dangerFg,
                ),
                title: Text('${m.kind.label} · ${m.supplyName}'),
                subtitle: Text(
                  '${m.byName}${m.at == null ? '' : ' · ${LimaTime.formatDateTime(m.at!)}'}'
                  '${m.orderId == null ? '' : '\nPedido ${m.orderId}'}'
                  '${m.reason.isEmpty ? '' : '\n${m.reason}'}',
                ),
                isThreeLine: m.reason.isNotEmpty || m.orderId != null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${m.delta > 0 ? '+' : ''}${Qty.format(m.delta)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '→ ${Qty.format(m.resulting)}',
                      style: const TextStyle(fontSize: 12),
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

class RecipesTab extends ConsumerWidget {
  const RecipesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(menuCatalogProvider);
    final supplies = ref.watch(suppliesProvider);
    final recipes = ref.watch(recipesProvider);
    return OrderAsyncView(
      value: catalog,
      onRetry: () => ref.invalidate(menuCatalogProvider),
      builder: (menu) => OrderAsyncView(
        value: supplies,
        onRetry: () => ref.invalidate(suppliesProvider),
        builder: (supplyList) {
          final byId = {for (final s in supplyList) s.id: s};
          final recipeById = {
            for (final r in recipes.value ?? const <Recipe>[]) r.dishId: r,
          };
          return PageBody(
            child: ListView(
              children: [
                const SectionHeader(
                  title: 'Recetas y costos',
                  subtitle: 'Costo por porción con el costo vigente de cada insumo, y margen sobre el precio.',
                ),
                if (menu.dishes.isEmpty)
                  const StateMessage(
                    icon: Icons.menu_book,
                    title: 'No hay platos en la carta.',
                  ),
                for (final d in menu.dishes)
                  _RecipeRow(
                    dish: d.name,
                    price: (d.price * 100).round(),
                    recipe: recipeById[d.id],
                    supplies: byId,
                    onEdit: () => showActionDialog(
                      context,
                      RecipeDialog(
                        dishId: d.id,
                        dishName: d.name,
                        priceCents: (d.price * 100).round(),
                        supplies: supplyList,
                        recipe: recipeById[d.id],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.dish,
    required this.price,
    required this.recipe,
    required this.supplies,
    required this.onEdit,
  });
  final String dish;
  final int price;
  final Recipe? recipe;
  final Map<String, Supply> supplies;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final has = r != null && r.ingredients.isNotEmpty;
    final cost = has ? r.cost(supplies) : 0;
    return Card(
      child: ListTile(
        title: Text(dish, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          has
              ? '${r.ingredients.length} insumos · costo ${_soles(cost)} · precio ${_soles(price)} · '
                    'margen ${_soles(price - cost)}${r.hasMissing(supplies) ? ' · ⚠ falta un insumo' : ''}'
              : 'Sin receta · precio ${_soles(price)}',
        ),
        trailing: TextButton(
          onPressed: onEdit,
          child: Text(has ? 'Editar' : 'Crear'),
        ),
      ),
    );
  }
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
