import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../menu/controllers/menu_providers.dart';
import '../../menu/models/dish.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/inventory_providers.dart';
import '../models/inventory_models.dart';
import '../widgets/inventory_dialogs.dart';

String _soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

/// Insumos (cocina): existencias, movimientos y recetas. Lo usan Cocina, Admin y
/// Superadmin. Los costos solo los ven Admin y Superadmin: las pantallas que
/// observan `supplyCostsProvider` se construyen únicamente para ellos.
class SuppliesScreen extends StatelessWidget {
  const SuppliesScreen({super.key});

  static const _tabs = [
    ('Insumos', Icons.inventory_2),
    ('Movimientos', Icons.swap_vert),
    ('Recetas', Icons.menu_book),
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
            children: [SuppliesTab(), MovementsTab(), RecipesTab()],
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

class _SupplyCard extends ConsumerWidget {
  const _SupplyCard({required this.supply});
  final Supply supply;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
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
            '${supply.stockLabel} · mínimo ${Qty.format(supply.minStock)} ${supply.unit.label}',
            style: const TextStyle(color: AppColors.inkMuted),
          ),
          // El costo solo existe para la administración.
          if (actorIsAdminOf(ref)) _SupplyCostLine(supply: supply),
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

/// Costo del insumo y botón para fijarlo. Solo se construye para Admin y
/// Superadmin: es el único sitio de esta pantalla que lee `costosInsumos`.
class _SupplyCostLine extends ConsumerWidget {
  const _SupplyCostLine({required this.supply});
  final Supply supply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = ref.watch(supplyCostsProvider).value?[supply.id] ?? 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            cost == 0
                ? 'Costo no registrado'
                : '${_soles(cost)} por ${supply.unit.label}',
            style: const TextStyle(color: AppColors.inkMuted),
          ),
        ),
        TextButton(
          onPressed: () => showActionDialog(
            context,
            SupplyCostDialog(supply: supply, cost: cost),
          ),
          child: const Text('Costo'),
        ),
      ],
    );
  }
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
                  title: 'Recetas',
                  subtitle: 'Insumos por porción de cada plato. El costo y el margen los ve la administración.',
                ),
                if (menu.dishes.isEmpty)
                  const StateMessage(
                    icon: Icons.menu_book,
                    title: 'No hay platos en la carta.',
                  ),
                for (final d in menu.dishes)
                  if (actorIsAdminOf(ref))
                    _AdminRecipeRow(
                      dish: d,
                      recipe: recipeById[d.id],
                      supplies: byId,
                      supplyList: supplyList,
                    )
                  else
                    _RecipeRow(
                      dish: d.name,
                      recipe: recipeById[d.id],
                      supplies: byId,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Receta para Cocina: ingredientes y cantidades, sin costos.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.dish,
    required this.recipe,
    required this.supplies,
  });
  final String dish;
  final Recipe? recipe;
  final Map<String, Supply> supplies;

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final has = r != null && r.ingredients.isNotEmpty;
    return Card(
      child: ListTile(
        title: Text(dish, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          has
              ? [
                  for (final i in r.ingredients)
                    '${Qty.format(i.qty)} ${supplies[i.supplyId]?.unit.label ?? ''} ${i.name}',
                ].join(' · ')
              : 'Sin receta',
        ),
      ),
    );
  }
}

/// Receta para la administración: costo por porción, margen y edición. Es el
/// único lugar de esta pantalla que lee los costos de los insumos.
class _AdminRecipeRow extends ConsumerWidget {
  const _AdminRecipeRow({
    required this.dish,
    required this.recipe,
    required this.supplies,
    required this.supplyList,
  });
  final Dish dish;
  final Recipe? recipe;
  final Map<String, Supply> supplies;
  final List<Supply> supplyList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costs = ref.watch(supplyCostsProvider).value ?? const <String, int>{};
    final price = (dish.price * 100).round();
    final r = recipe;
    final has = r != null && r.ingredients.isNotEmpty;
    final cost = has ? r.cost(costs) : 0;
    return Card(
      child: ListTile(
        title: Text(
          dish.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          has
              ? '${r.ingredients.length} insumos · costo ${_soles(cost)} · precio ${_soles(price)} · '
                    'margen ${_soles(price - cost)}${r.hasMissing(supplies) ? ' · ⚠ falta un insumo' : ''}'
              : 'Sin receta · precio ${_soles(price)}',
        ),
        trailing: TextButton(
          onPressed: () => showActionDialog(
            context,
            RecipeDialog(
              dishId: dish.id,
              dishName: dish.name,
              priceCents: price,
              supplies: supplyList,
              costs: costs,
              recipe: recipe,
            ),
          ),
          child: Text(has ? 'Editar' : 'Crear'),
        ),
      ),
    );
  }
}
