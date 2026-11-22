import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/controllers/role_providers.dart';
import '../../roles/models/permission.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../controllers/menu_providers.dart';
import '../models/dish.dart';
import '../widgets/dish_image.dart';
import '../widgets/menu_async_view.dart';
import '../widgets/menu_editor.dart';

class MenuAdminScreen extends ConsumerWidget {
  const MenuAdminScreen({super.key});
  void _edit(BuildContext context, Widget editor) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => editor,
  );

  /// Disponibilidad al instante, sin abrir el editor (se agotó o volvió).
  Future<void> _setAvailable(
    BuildContext context,
    WidgetRef ref,
    Dish dish,
    bool available,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(menuServiceProvider)
          .saveDish(dish.copyWith(available: available));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ErrorMapper.map(error).message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated ||
        !ref
            .watch(permissionServiceProvider)
            .can(session.user.role, Permission.manageMenu)) {
      return const Center(
        child: Text('No tienes permisos para administrar la carta.'),
      );
    }
    return MenuAsyncView(
      builder: (catalog) => PageBody(
        child: ListView(
          children: [
            const SectionHeader(title: 'Administración de la carta'),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _edit(context, const MenuEditor.category()),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva categoría'),
                ),
                FilledButton.icon(
                  onPressed: catalog.categories.any((c) => c.active)
                      ? () => _edit(
                          context,
                          MenuEditor.dish(categories: catalog.categories),
                        )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo plato'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Categorías', style: Theme.of(context).textTheme.titleLarge),
            if (catalog.categories.isEmpty)
              const Text('Crea una categoría antes de agregar platos.'),
            for (final category in catalog.categories)
              Card(
                child: ListTile(
                  title: Text(category.name),
                  subtitle: Text(
                    '${category.active ? 'Activa' : 'Inactiva'} · ${catalog.dishesFor(category.id).length} platos',
                  ),
                  trailing: IconButton(
                    tooltip: 'Editar categoría',
                    icon: const Icon(Icons.edit),
                    onPressed: () =>
                        _edit(context, MenuEditor.category(category: category)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('Platos', style: Theme.of(context).textTheme.titleLarge),
            if (catalog.dishes.isEmpty)
              const Text('Aún no hay platos registrados.'),
            for (final dish in catalog.dishes)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: DishImage(dishId: dish.id, url: dish.imageUrl),
                    ),
                  ),
                  title: Text(dish.name),
                  subtitle: Text(
                    'S/ ${dish.price.toStringAsFixed(2)} · ${dish.available ? 'Disponible' : 'No disponible'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: dish.available,
                        onChanged: (v) => _setAvailable(context, ref, dish, v),
                      ),
                      IconButton(
                        tooltip: 'Editar plato',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(
                          context,
                          MenuEditor.dish(
                            dish: dish,
                            categories: catalog.categories,
                          ),
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
}
