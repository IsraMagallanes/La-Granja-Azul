import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/utensil_models.dart';
import '../repositories/utensil_repository.dart';
import '../services/utensil_service.dart';

final utensilRepositoryProvider = Provider<UtensilRepository>(
  (ref) => throw UnimplementedError('utensilRepositoryProvider sin override'),
);
final utensilServiceProvider = Provider<UtensilService>(
  (ref) => UtensilService(ref.watch(utensilRepositoryProvider)),
);

final utensilsProvider = StreamProvider.autoDispose<List<Utensil>>(
  (ref) => ref.watch(utensilRepositoryProvider).watchUtensils(),
  retry: (_, _) => null,
);
final utensilAssignmentsProvider =
    StreamProvider.autoDispose<List<UtensilAssignment>>(
      (ref) => ref.watch(utensilRepositoryProvider).watchAssignments(),
      retry: (_, _) => null,
    );
final utensilMovementsProvider =
    StreamProvider.autoDispose<List<UtensilMovement>>(
      (ref) => ref.watch(utensilRepositoryProvider).watchMovements(),
      retry: (_, _) => null,
    );

/// Meseros activos a los que se puede entregar (directorio mínimo, sin datos
/// personales): lo pueden leer el Mesero y la administración.
final waiterDirectoryProvider = StreamProvider.autoDispose<List<WaiterRef>>(
  (ref) => ref
      .watch(utensilRepositoryProvider)
      .watchWaiters()
      .map((l) => [
        for (final w in l)
          if (w.active) w,
      ]),
  retry: (_, _) => null,
);

/// Costos por versión de utensilio. Solo Admin y Superadmin pueden leerlos: las
/// pantallas del Mesero NUNCA deben observar este proveedor.
final utensilCostsProvider = StreamProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(utensilRepositoryProvider).watchCosts(),
  retry: (_, _) => null,
);
