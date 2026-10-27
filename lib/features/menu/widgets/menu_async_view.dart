import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../controllers/menu_providers.dart';

class MenuAsyncView extends ConsumerWidget {
  const MenuAsyncView({super.key, required this.builder});
  final Widget Function(MenuCatalog) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(menuCatalogProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ErrorMapper.map(error).message),
              TextButton(
                onPressed: () => ref.invalidate(menuCatalogProvider),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: builder,
      );
}
