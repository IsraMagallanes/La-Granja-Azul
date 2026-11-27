import '../../../core/error/app_failure.dart';
import '../../users/models/app_user.dart';
import '../models/utensil_models.dart';
import '../repositories/utensil_repository.dart';

abstract final class UtensilValidation {
  static const maxQuantity = 1000000;
  static const maxCost =
      10000000; // S/ 100,000.00 por unidad, igual que las reglas

  static String? name(String? v) {
    final t = (v ?? '').trim();
    return t.length < 2 || t.length > 60 ? 'Entre 2 y 60 caracteres.' : null;
  }

  /// Entero positivo (los utensilios se cuentan por unidades).
  static int? quantity(String? text) {
    final t = (text ?? '').trim();
    if (!RegExp(r'^\d{1,7}$').hasMatch(t)) return null;
    final n = int.parse(t);
    return n >= 1 && n <= maxQuantity ? n : null;
  }

  static String? quantityError(String? text) =>
      quantity(text) == null ? 'Número entero entre 1 y $maxQuantity.' : null;

  static String? reason(String? v) =>
      (v ?? '').trim().length < 3 || (v ?? '').trim().length > 120
      ? 'Motivo de 3 a 120 caracteres.'
      : null;
}

class UtensilService {
  const UtensilService(this.repository);
  final UtensilRepository repository;

  Never _fail(String message) => throw AppFailure(message);

  bool _isAdmin(AppUser a) =>
      a.role.value == 'admin' || a.role.value == 'superadmin';

  /// Catálogo: solo Admin y Superadmin. [newUnitCost] = centavos; null = sin
  /// cambio de costo (0 al crear = sin costo registrado).
  Future<void> saveUtensil(
    AppUser actor, {
    Utensil? current,
    required String name,
    required int minStock,
    required bool active,
    int? newUnitCost,
  }) async {
    if (!_isAdmin(actor)) _fail('Solo la administración gestiona el catálogo.');
    final error = UtensilValidation.name(name);
    if (error != null) _fail('Nombre: $error');
    if (minStock < 0 || minStock > UtensilValidation.maxQuantity) {
      _fail('El stock mínimo no es válido.');
    }
    if (newUnitCost != null &&
        (newUnitCost < 0 || newUnitCost > UtensilValidation.maxCost)) {
      _fail('El costo no es válido.');
    }
    return repository.saveUtensil(
      actor,
      id: current?.id,
      name: name.trim(),
      minStock: minStock,
      active: current == null ? true : active,
      newUnitCost: newUnitCost,
    );
  }

  /// Registra un movimiento. Mesero: entregas, devoluciones, pérdidas, daños y
  /// deterioros; alta y ajuste solo Admin/Superadmin. Las operaciones sobre un
  /// mesero exigen elegirlo (UID y nombre quedan en el movimiento).
  Future<void> register(
    AppUser actor,
    Utensil utensil,
    UtensilKind kind,
    int quantity,
    String reason, {
    WaiterRef? waiter,
    bool increase = true,
  }) async {
    if (kind.adminOnly && !_isAdmin(actor)) {
      _fail('Solo la administración registra altas y ajustes.');
    }
    if (!utensil.active) _fail('El utensilio está desactivado.');
    if (quantity < 1 || quantity > UtensilValidation.maxQuantity) {
      _fail('La cantidad no es válida.');
    }
    if (kind.toWaiter && waiter == null) _fail('Elige al mesero.');
    if (!kind.toWaiter && waiter != null) {
      _fail('Este movimiento no se asigna a un mesero.');
    }
    if (kind.needsReason) {
      final error = UtensilValidation.reason(reason);
      if (error != null) _fail(error);
    } else if (reason.trim().length > 120) {
      _fail('Motivo de 120 caracteres como máximo.');
    }
    final sign = kind == UtensilKind.ajuste && !increase ? -1 : 1;
    if (kind == UtensilKind.entrega && quantity > utensil.available) {
      _fail('Solo hay ${utensil.available} disponibles.');
    }
    if (kind == UtensilKind.ajuste &&
        sign < 0 &&
        quantity > utensil.available) {
      _fail('Solo hay ${utensil.available} disponibles.');
    }
    return repository.registerMovement(
      actor,
      utensilId: utensil.id,
      kind: kind,
      quantity: quantity,
      reason: reason.trim(),
      waiter: waiter,
      sign: sign,
    );
  }
}
