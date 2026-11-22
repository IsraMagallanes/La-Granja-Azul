import '../../../core/error/app_failure.dart';
import '../models/inventory_models.dart';

/// Un insumo a descontar de un pedido y el stock que tenía al calcularlo.
class ConsumptionLine {
  const ConsumptionLine({required this.supply, required this.qty});
  final Supply supply;

  /// Cantidad total a descontar (milésimas de la unidad del insumo).
  final int qty;
  int get resulting => supply.stock - qty;
}

/// Un insumo al que le falta stock para el pedido.
class StockShortage {
  const StockShortage({required this.supply, required this.needed});
  final Supply supply;

  /// Lo que pide el pedido.
  final int needed;

  /// Lo que se puede descontar: nunca más que el stock disponible.
  int get discounted => supply.stock < needed ? supply.stock : needed;
  int get missing => needed - discounted;

  Map<String, dynamic> toMap() => {
    'insumoId': supply.id,
    'insumo': supply.name,
    'necesario': needed,
    'descontado': discounted,
    'faltante': missing,
  };
}

/// Falta stock para un pedido. Lleva los faltantes para que un administrador
/// pueda forzar el «Listo» con motivo.
class InsufficientStockFailure extends AppFailure {
  InsufficientStockFailure(this.shortages)
    : super(
        'No hay stock suficiente: ${[for (final s in shortages) '«${s.supply.name}» necesita ${Qty.format(s.needed)} ${s.supply.unit.label} y hay ${s.supply.stockLabel}'].join('; ')}.',
        code: 'stock-insuficiente',
      );
  final List<StockShortage> shortages;
}

/// Resultado del cálculo: qué se descuenta y qué quedó fuera (para la auditoría).
class ConsumptionPlan {
  const ConsumptionPlan({
    required this.lines,
    required this.dishesWithoutRecipe,
    required this.skippedSupplies,
    this.shortages = const [],
  });

  /// Ordenadas por insumo: la posición es la `linea` del movimiento. Solo
  /// incluye insumos con algo que descontar.
  final List<ConsumptionLine> lines;

  /// Platos del pedido sin receta (o con receta vacía): no descuentan nada.
  final int dishesWithoutRecipe;

  /// Insumos de recetas que ya no existen o están desactivados: no se descuentan.
  final int skippedSupplies;

  /// Faltantes (solo si se permitió forzar): se descuenta lo disponible.
  final List<StockShortage> shortages;
}

/// Calcula el descuento de inventario de un pedido a partir de sus platos y
/// recetas. Es una función pura: la transacción de Firestore le pasa lo leído.
abstract final class ConsumptionPlanner {
  /// Máximo de insumos distintos por pedido. Provisional (como las líneas de
  /// compra): lo limitan los accesos a documentos que las reglas permiten por
  /// lote; debe validarse en Firebase real.
  static const maxSupplies = 8;

  /// Insumos y cantidades que pide el pedido: receta × porciones, acumulado por
  /// insumo. [portions] va de plato a cantidad pedida.
  static Map<String, int> needs(
    Map<String, int> portions,
    Map<String, Recipe?> recipes,
  ) {
    final needs = <String, int>{};
    for (final e in portions.entries) {
      final recipe = recipes[e.key];
      if (recipe == null) continue;
      for (final i in recipe.ingredients) {
        needs[i.supplyId] = (needs[i.supplyId] ?? 0) + i.qty * e.value;
      }
    }
    return needs;
  }

  static int dishesWithoutRecipe(
    Map<String, int> portions,
    Map<String, Recipe?> recipes,
  ) => [
    for (final d in portions.keys)
      if ((recipes[d]?.ingredients ?? const []).isEmpty) d,
  ].length;

  /// Verifica el stock y arma las líneas. Si algún insumo no alcanza lanza
  /// [InsufficientStockFailure] (no se descuenta nada), salvo con
  /// [allowShortage]: entonces descuenta lo disponible y devuelve los faltantes.
  /// Lanza [AppFailure] si el pedido usa más de [maxSupplies].
  static ConsumptionPlan plan({
    required Map<String, int> needs,
    required Map<String, Supply?> supplies,
    required int dishesWithoutRecipe,
    bool allowShortage = false,
  }) {
    final lines = <ConsumptionLine>[];
    final shortages = <StockShortage>[];
    var skipped = 0;
    var considered = 0;
    final ids = needs.keys.toList()..sort();
    for (final id in ids) {
      final supply = supplies[id];
      if (supply == null || !supply.active) {
        skipped++;
        continue;
      }
      considered++;
      final qty = needs[id]!;
      if (qty > Qty.max) {
        throw AppFailure('La cantidad de «${supply.name}» es demasiado alta.');
      }
      if (supply.stock < qty) {
        shortages.add(StockShortage(supply: supply, needed: qty));
        if (supply.stock > 0) {
          lines.add(ConsumptionLine(supply: supply, qty: supply.stock));
        }
        continue;
      }
      lines.add(ConsumptionLine(supply: supply, qty: qty));
    }
    if (considered > maxSupplies) {
      throw const AppFailure(
        'El pedido usa más de $maxSupplies insumos distintos y no se puede '
        'descontar de una vez. Avisa a la administración.',
      );
    }
    if (shortages.isNotEmpty && !allowShortage) {
      throw InsufficientStockFailure(shortages);
    }
    return ConsumptionPlan(
      lines: lines,
      dishesWithoutRecipe: dishesWithoutRecipe,
      skippedSupplies: skipped,
      shortages: shortages,
    );
  }
}
