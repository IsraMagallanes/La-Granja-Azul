import '../models/inventory_models.dart';

abstract interface class InventoryRepository {
  Stream<List<Supply>> watchSupplies();
  Stream<List<StockMovement>> watchMovements();
  Stream<List<Supplier>> watchSuppliers();
  Stream<List<Purchase>> watchPurchases();
  Stream<List<Recipe>> watchRecipes();

  /// Costos vigentes por insumo (centavos por unidad entera), de
  /// `costosInsumos`: solo Admin y Superadmin pueden leerlos.
  Stream<Map<String, int>> watchSupplyCosts();

  Future<void> createSupply(String name, SupplyUnit unit, int minStock);
  Future<void> editSupply(
    String id, {
    required String name,
    required int minStock,
    required bool active,
  });

  /// Fija el costo de un insumo (solo Admin y Superadmin).
  Future<void> setSupplyCost(
    String id,
    int unitCost, {
    required String actorUid,
  });

  /// Cambia el stock en [delta] (con signo) y deja su movimiento, en una sola
  /// transacción que rechaza un stock negativo.
  Future<void> moveStock(
    String supplyId,
    MovementKind kind,
    int delta,
    String reason, {
    required String actorUid,
  });

  Future<void> saveSupplier(
    String? id, {
    required String name,
    required String ruc,
    required String phone,
    required String contact,
    required bool active,
  });

  Future<void> createPurchase(
    Supplier supplier,
    List<PurchaseLine> lines, {
    required String actorUid,
  });

  /// Recibe una compra pendiente: la cierra, suma el stock de cada línea con su
  /// movimiento y fija el costo del insumo en `costosInsumos`, todo en una
  /// transacción.
  Future<void> receivePurchase(String id, {required String actorUid});
  Future<void> cancelPurchase(
    String id,
    String reason, {
    required String actorUid,
  });

  Future<void> saveRecipe(
    String dishId,
    List<RecipeIngredient> ingredients, {
    required String actorUid,
  });
}
