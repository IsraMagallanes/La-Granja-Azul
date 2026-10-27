import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../widgets/menu_async_view.dart';
import '../widgets/dish_image.dart';

class PublicMenuScreen extends StatelessWidget {
  const PublicMenuScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppConfig.appName)),
    body: MenuAsyncView(
      builder: (catalog) {
        final categories = catalog.categories.where((c) => c.active).toList();
        if (categories.isEmpty) {
          return const Center(
            child: Text('Aún no hay categorías en la carta.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Nuestra carta',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            for (final category in categories) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  category.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (catalog.dishesFor(category.id).isEmpty)
                const Text(
                  'Próximamente encontrarás platos en esta categoría.',
                ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final dish in catalog.dishesFor(category.id))
                    SizedBox(
                      width: 320,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DishImage(url: dish.imageUrl),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dish.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  Text(dish.description),
                                  Text('S/ ${dish.price.toStringAsFixed(2)}'),
                                  Chip(
                                    label: Text(
                                      dish.available
                                          ? 'Disponible'
                                          : 'No disponible',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}
