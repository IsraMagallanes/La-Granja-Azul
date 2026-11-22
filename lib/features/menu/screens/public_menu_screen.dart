import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/dish.dart';
import '../widgets/dish_image.dart';
import '../widgets/menu_async_view.dart';

/// Carta pública (sin login, carrito ni pedidos): encabezado azul marino,
/// filtros por categoría y platos con fotografía, como en la referencia.
class PublicMenuScreen extends StatefulWidget {
  const PublicMenuScreen({super.key});

  @override
  State<PublicMenuScreen> createState() => _PublicMenuScreenState();
}

class _PublicMenuScreenState extends State<PublicMenuScreen> {
  String? _categoryId; // null = Todos

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.white,
    body: Column(
      children: [
        const _Hero(),
        Expanded(
          child: MenuAsyncView(
            builder: (catalog) {
              final categories = catalog.categories
                  .where((c) => c.active)
                  .toList();
              if (categories.isEmpty) {
                return const Center(
                  child: Text('Aún no hay categorías en la carta.'),
                );
              }
              final selected = categories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null;
              final shown = selected == null
                  ? categories
                  : categories.where((c) => c.id == selected).toList();
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterPill(
                              label: 'Todos',
                              selected: selected == null,
                              onTap: () => setState(() => _categoryId = null),
                            ),
                            for (final c in categories) ...[
                              const SizedBox(width: 8),
                              FilterPill(
                                label: c.name,
                                selected: selected == c.id,
                                onTap: () => setState(() => _categoryId = c.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                      for (final category in shown) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 8),
                          child: Text(
                            category.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (catalog.dishesFor(category.id).isEmpty)
                          const Text(
                            'Próximamente encontrarás platos en esta categoría.',
                            style: TextStyle(color: AppColors.inkMuted),
                          ),
                        LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth >= 760 ? 2 : 1;
                            final w = (c.maxWidth - 16 * (cols - 1)) / cols;
                            return Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              children: [
                                for (final (i, dish) in _availableFirst(
                                  catalog.dishesFor(category.id),
                                ).indexed)
                                  SizedBox(width: w, child: _DishRow(dish, i)),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// Los platos agotados van al final de su categoría, sin ocultarlos.
List<Dish> _availableFirst(List<Dish> dishes) => [
  ...dishes.where((d) => d.available),
  ...dishes.where((d) => !d.available),
];

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) => BrandBackdrop(
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandWordmark(size: 22),
            const SizedBox(height: 28),
            Text(
              'Nuestra Carta',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Disfruta el mejor sabor en La Granja Azul',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DishRow extends StatelessWidget {
  const _DishRow(this.dish, this.index);

  final Dish dish;
  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Reveal(
      index: index,
      child: Interactive(
        hoverScale: 1.02,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _DishDetail(dish),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Opacity(
                    opacity: dish.available ? 1 : 0.55,
                    child: DishImage(dishId: dish.id, url: dish.imageUrl),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dish.name,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          dish.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'S/ ${dish.price.toStringAsFixed(2)}',
                              style: text.titleMedium?.copyWith(
                                color: AppColors.blue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            StatusPill(
                              dish.available ? 'Disponible' : 'No disponible',
                              tone: dish.available
                                  ? StatusTone.success
                                  : StatusTone.neutral,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ficha del plato: foto grande, descripción completa, precio y disponibilidad.
class _DishDetail extends StatelessWidget {
  const _DishDetail(this.dish);

  final Dish dish;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: dish.available ? 1 : 0.55,
                child: DishImage(
                  dishId: dish.id,
                  url: dish.imageUrl,
                  height: 240,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.name,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'S/ ${dish.price.toStringAsFixed(2)}',
                          style: text.titleLarge?.copyWith(
                            color: AppColors.blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        StatusPill(
                          dish.available ? 'Disponible' : 'No disponible',
                          tone: dish.available
                              ? StatusTone.success
                              : StatusTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(dish.description),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
