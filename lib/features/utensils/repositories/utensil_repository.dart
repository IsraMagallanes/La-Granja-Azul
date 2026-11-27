import '../../users/models/app_user.dart';
import '../models/utensil_models.dart';

abstract interface class UtensilRepository {
  Stream<List<Utensil>> watchUtensils();
  Stream<List<UtensilAssignment>> watchAssignments();
  Stream<List<UtensilMovement>> watchMovements();

  /// Directorio mínimo de meseros (UID, nombre y estado): sin datos personales.
  Stream<List<WaiterRef>> watchWaiters();

  /// Alinea el directorio con el personal (solo Admin/Superadmin). Devuelve
  /// cuántos documentos escribió; no escribe nada si ya coincide.
  Future<int> syncWaiterDirectory(List<WaiterRef> staff);

  /// Costos por versión (`{utensilio}_{n}` → centavos). Solo Admin/Superadmin.
  Stream<Map<String, int>> watchCosts();

  /// Alta o edición del catálogo con su auditoría (mismo lote). [newUnitCost]
  /// crea una versión de costo nueva (inmutable); null = no cambia el costo.
  Future<void> saveUtensil(
    AppUser actor, {
    String? id,
    required String name,
    required int minStock,
    required bool active,
    int? newUnitCost,
  });

  /// Registra un movimiento y actualiza existencias y asignación en una sola
  /// transacción (sin stock negativo). En un ajuste, [sign] da el signo.
  Future<void> registerMovement(
    AppUser actor, {
    required String utensilId,
    required UtensilKind kind,
    required int quantity,
    required String reason,
    WaiterRef? waiter,
    int sign = 1,
  });
}
