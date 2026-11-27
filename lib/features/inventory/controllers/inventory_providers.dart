import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/inventory_models.dart';
import '../repositories/inventory_repository.dart';
import '../services/inventory_service.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => throw UnimplementedError('inventoryRepositoryProvider sin override'),
);
final inventoryServiceProvider = Provider<InventoryService>(
  (ref) => InventoryService(ref.watch(inventoryRepositoryProvider)),
);

final suppliesProvider = StreamProvider.autoDispose<List<Supply>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchSupplies(),
  retry: (_, _) => null,
);
final stockMovementsProvider = StreamProvider.autoDispose<List<StockMovement>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchMovements(),
  retry: (_, _) => null,
);
final suppliersProvider = StreamProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchSuppliers(),
  retry: (_, _) => null,
);
final purchasesProvider = StreamProvider.autoDispose<List<Purchase>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchPurchases(),
  retry: (_, _) => null,
);

/// Costos de insumos. Solo Admin y Superadmin pueden leerlos: las pantallas de
/// Cocina NUNCA deben observar este proveedor.
final supplyCostsProvider = StreamProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchSupplyCosts(),
  retry: (_, _) => null,
);
final recipesProvider = StreamProvider.autoDispose<List<Recipe>>(
  (ref) => ref.watch(inventoryRepositoryProvider).watchRecipes(),
  retry: (_, _) => null,
);
