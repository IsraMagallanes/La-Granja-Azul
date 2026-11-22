import '../../../core/error/app_failure.dart';
import '../models/inventory_models.dart';
import '../repositories/inventory_repository.dart';

abstract final class InventoryValidation {
  static const maxCost =
      10000000; // S/ 100,000.00 por unidad, igual que las reglas
  static const maxLines =
      8; // provisional: validar en Firebase real (ver README)
  static const maxIngredients = 30;

  static String? name(String? v, {int min = 2, int max = 60}) {
    final t = (v ?? '').trim();
    return t.length < min || t.length > max
        ? 'Entre $min y $max caracteres.'
        : null;
  }

  static String? ruc(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty || RegExp(r'^\d{11}$').hasMatch(t)
        ? null
        : 'El RUC tiene 11 dígitos (o déjalo vacío).';
  }

  static String? reason(String? v) =>
      (v ?? '').trim().length < 3 || (v ?? '').trim().length > 120
      ? 'Motivo de 3 a 120 caracteres.'
      : null;
}

class InventoryService {
  const InventoryService(this.repository);
  final InventoryRepository repository;

  Never _fail(String message) => throw AppFailure(message);

  Future<void> createSupply(
    String name,
    SupplyUnit unit,
    int minStock,
    int unitCost,
  ) async {
    final error = InventoryValidation.name(name);
    if (error != null) _fail('Nombre: $error');
    _checkAmounts(minStock, unitCost);
    return repository.createSupply(name.trim(), unit, minStock, unitCost);
  }

  Future<void> editSupply(
    Supply supply, {
    required String name,
    required int minStock,
    required int unitCost,
    required bool active,
  }) async {
    final error = InventoryValidation.name(name);
    if (error != null) _fail('Nombre: $error');
    _checkAmounts(minStock, unitCost);
    return repository.editSupply(
      supply.id,
      name: name.trim(),
      minStock: minStock,
      unitCost: unitCost,
      active: active,
    );
  }

  void _checkAmounts(int minStock, int unitCost) {
    if (minStock < 0 || minStock > Qty.max)
      _fail('El stock mínimo no es válido.');
    if (unitCost < 0 || unitCost > InventoryValidation.maxCost) {
      _fail('El costo no es válido.');
    }
  }

  /// [quantity] siempre positiva: el tipo decide el signo. En un ajuste, el
  /// signo lo da [increase].
  Future<void> moveStock(
    Supply supply,
    MovementKind kind,
    int quantity,
    String reason, {
    bool increase = true,
    required String actorUid,
  }) async {
    if (kind == MovementKind.compra) {
      _fail('Las compras se registran recibiendo una compra.');
    }
    if (quantity <= 0 || quantity > Qty.max) _fail('La cantidad no es válida.');
    if (!supply.active) _fail('El insumo está desactivado.');
    final error = InventoryValidation.reason(reason);
    if (error != null) _fail(error);
    final sign = kind == MovementKind.ajuste ? (increase ? 1 : -1) : kind.sign;
    final delta = sign * quantity;
    if (supply.stock + delta < 0) {
      _fail('No hay stock suficiente (${supply.stockLabel}).');
    }
    if (supply.stock + delta > Qty.max)
      _fail('El stock resultante es demasiado alto.');
    return repository.moveStock(
      supply.id,
      kind,
      delta,
      reason.trim(),
      actorUid: actorUid,
    );
  }

  Future<void> saveSupplier(
    Supplier? current, {
    required String name,
    required String ruc,
    required String phone,
    required String contact,
    required bool active,
  }) async {
    final error =
        InventoryValidation.name(name, max: 80) ?? InventoryValidation.ruc(ruc);
    if (error != null) _fail(error);
    if (phone.trim().length > 20 || contact.trim().length > 80) {
      _fail('Teléfono (20) o contacto (80) demasiado largo.');
    }
    return repository.saveSupplier(
      current?.id,
      name: name.trim(),
      ruc: ruc.trim(),
      phone: phone.trim(),
      contact: contact.trim(),
      active: active,
    );
  }

  Future<void> createPurchase(
    Supplier? supplier,
    List<PurchaseLine> lines, {
    required String actorUid,
  }) async {
    if (supplier == null || !supplier.active) {
      _fail('Elige un proveedor activo.');
    }
    if (lines.isEmpty) _fail('Agrega al menos un insumo.');
    if (lines.length > InventoryValidation.maxLines) {
      _fail('Una compra admite hasta ${InventoryValidation.maxLines} insumos.');
    }
    if (lines.map((l) => l.supplyId).toSet().length != lines.length) {
      _fail('Un insumo solo puede aparecer una vez en la compra.');
    }
    for (final l in lines) {
      if (l.qty <= 0 || l.qty > Qty.max)
        _fail('Cantidad no válida en «${l.name}».');
      if (l.unitCost < 0 || l.unitCost > InventoryValidation.maxCost) {
        _fail('Costo no válido en «${l.name}».');
      }
    }
    return repository.createPurchase(supplier, lines, actorUid: actorUid);
  }

  /// Quien creó la compra no la recibe, salvo Admin y Superadmin ([isAdmin]).
  Future<void> receivePurchase(
    Purchase purchase, {
    required String actorUid,
    bool isAdmin = false,
  }) async {
    if (purchase.status != PurchaseStatus.pendiente) {
      _fail('Esta compra ya no está pendiente.');
    }
    if (purchase.invalidLines > 0) {
      _fail('La compra tiene líneas ilegibles y no se puede recibir.');
    }
    if (!isAdmin && purchase.createdBy == actorUid) {
      _fail('La compra debe recibirla otra persona de Almacén.');
    }
    return repository.receivePurchase(purchase.id, actorUid: actorUid);
  }

  Future<void> cancelPurchase(
    Purchase purchase,
    String reason, {
    required String actorUid,
  }) async {
    if (purchase.status != PurchaseStatus.pendiente) {
      _fail('Esta compra ya no está pendiente.');
    }
    final error = InventoryValidation.reason(reason);
    if (error != null) _fail(error);
    return repository.cancelPurchase(
      purchase.id,
      reason.trim(),
      actorUid: actorUid,
    );
  }

  Future<void> saveRecipe(
    String dishId,
    List<RecipeIngredient> ingredients, {
    required String actorUid,
  }) async {
    if (ingredients.length > InventoryValidation.maxIngredients) {
      _fail(
        'Una receta admite hasta ${InventoryValidation.maxIngredients} insumos.',
      );
    }
    if (ingredients.map((i) => i.supplyId).toSet().length !=
        ingredients.length) {
      _fail('Un insumo solo puede aparecer una vez en la receta.');
    }
    if (ingredients.any((i) => i.qty <= 0 || i.qty > Qty.max)) {
      _fail('Todas las cantidades deben ser mayores que cero.');
    }
    return repository.saveRecipe(dishId, ingredients, actorUid: actorUid);
  }
}
