import '../../users/models/app_user.dart';

/// Cantidades en milésimas de la unidad (1.5 kg = 1500), siempre enteras; los
/// costos son centavos de sol por unidad entera (S/ 12.00 el kg = 1200).
abstract final class Qty {
  static const max = 1000000000;

  /// «1.5» → 1500; null si no es una cantidad válida (hasta 3 decimales).
  static int? parse(String? text) {
    final t = (text ?? '').trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,6}(\.\d{1,3})?$').hasMatch(t)) return null;
    final parts = t.split('.');
    final decimals = parts.length == 1 ? '000' : parts[1].padRight(3, '0');
    return int.parse(parts[0]) * 1000 + int.parse(decimals);
  }

  static String? validate(String? text, {bool allowZero = false}) {
    final value = parse(text);
    if (value == null) return 'Cantidad válida, p. ej. 1.5.';
    if (!allowZero && value == 0) return 'Debe ser mayor que cero.';
    return null;
  }

  /// 1500 → «1.5»; 2000 → «2».
  static String format(int milli) {
    final sign = milli < 0 ? '-' : '';
    final v = milli.abs();
    final whole = v ~/ 1000;
    final frac = (v % 1000)
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$sign$whole${frac.isEmpty ? '' : '.$frac'}';
  }

  /// Costo en centavos de [milli] de un insumo que cuesta [unitCostCents] por
  /// unidad entera.
  static int cost(int milli, int unitCostCents) =>
      (milli * unitCostCents / 1000).round();
}

enum SupplyUnit {
  kg('kg'),
  g('g'),
  l('l'),
  ml('ml'),
  und('und');

  const SupplyUnit(this.label);
  final String label;
}

class Supply {
  const Supply({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.minStock,
    required this.unitCost,
    required this.active,
  });
  final String id;
  final String name;
  final SupplyUnit unit;
  final int stock;
  final int minStock;
  final int unitCost;
  final bool active;

  bool get isLow => active && minStock > 0 && stock <= minStock;
  bool get isOut => stock <= 0;
  String get stockLabel => '${Qty.format(stock)} ${unit.label}';

  factory Supply.fromMap(String id, Map<String, dynamic> d) => Supply(
    id: id,
    name: d['nombre'] as String,
    unit: SupplyUnit.values.byName(d['unidad'] as String),
    stock: d['stock'] as int,
    minStock: d['stockMinimo'] as int,
    unitCost: d['costoUnitario'] as int,
    active: d['activo'] as bool,
  );
}

enum MovementKind {
  entrada('Entrada', 1),
  salida('Salida', -1),
  merma('Merma', -1),
  ajuste('Ajuste', 0),
  compra('Compra', 1),

  /// Descuento automático al marcar «Listo» un pedido (Fase 8B).
  consumo('Consumo', -1);

  const MovementKind(this.label, this.sign);
  final String label;

  /// 1 suma, -1 resta, 0 = el signo lo elige quien ajusta.
  final int sign;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.supplyId,
    required this.supplyName,
    required this.kind,
    required this.delta,
    required this.resulting,
    required this.reason,
    required this.byName,
    this.orderId,
    this.at,
  });
  final String id;
  final String supplyId;
  final String supplyName;
  final MovementKind kind;
  final int delta;
  final int resulting;
  final String reason;
  final String byName;

  /// Pedido que originó un consumo automático.
  final String? orderId;
  final DateTime? at;

  factory StockMovement.fromMap(String id, Map<String, dynamic> d) =>
      StockMovement(
        id: id,
        supplyId: d['insumoId'] as String,
        supplyName: d['insumoNombre'] as String,
        kind: MovementKind.values.byName(d['tipo'] as String),
        delta: d['delta'] as int,
        resulting: d['stockResultante'] as int,
        reason: (d['motivo'] as String?) ?? '',
        byName: (d['creadoPorNombre'] as String?) ?? '',
        orderId: d['pedidoId'] as String?,
        at: toDateOrNull(d['creadoEn']),
      );
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.ruc,
    required this.phone,
    required this.contact,
    required this.active,
  });
  final String id;
  final String name;
  final String ruc;
  final String phone;
  final String contact;
  final bool active;

  factory Supplier.fromMap(String id, Map<String, dynamic> d) => Supplier(
    id: id,
    name: d['nombre'] as String,
    ruc: (d['ruc'] as String?) ?? '',
    phone: (d['telefono'] as String?) ?? '',
    contact: (d['contacto'] as String?) ?? '',
    active: d['activo'] as bool,
  );
}

class PurchaseLine {
  const PurchaseLine({
    required this.supplyId,
    required this.name,
    required this.qty,
    required this.unitCost,
  });
  final String supplyId;
  final String name;
  final int qty;
  final int unitCost;
  int get subtotal => Qty.cost(qty, unitCost);

  /// Línea mal formada (documento alterado fuera de la app): null.
  static PurchaseLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['insumoId'];
    final name = raw['nombre'];
    final qty = raw['cantidad'];
    final cost = raw['costoUnitario'];
    if (id is! String || name is! String || qty is! int || cost is! int) {
      return null;
    }
    if (qty <= 0 || cost < 0) return null;
    return PurchaseLine(supplyId: id, name: name, qty: qty, unitCost: cost);
  }

  Map<String, dynamic> toMap() => {
    'insumoId': supplyId,
    'nombre': name,
    'cantidad': qty,
    'costoUnitario': unitCost,
    'subtotal': subtotal,
  };
}

enum PurchaseStatus {
  pendiente('Pendiente'),
  recibida('Recibida'),
  cancelada('Cancelada');

  const PurchaseStatus(this.label);
  final String label;
}

class Purchase {
  const Purchase({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.lines,
    required this.status,
    required this.byName,
    this.createdBy,
    this.invalidLines = 0,
    this.at,
    this.receivedAt,
    this.cancelReason,
  });
  final String id;
  final String supplierId;
  final String supplierName;
  final List<PurchaseLine> lines;
  final PurchaseStatus status;
  final String byName;
  final String? createdBy;

  /// Líneas ilegibles del documento: con alguna, la compra no se puede recibir.
  final int invalidLines;
  final DateTime? at;
  final DateTime? receivedAt;
  final String? cancelReason;

  /// No se guarda: es la suma de los subtotales de las líneas.
  int get total => lines.fold(0, (a, l) => a + l.subtotal);

  factory Purchase.fromMap(String id, Map<String, dynamic> d) {
    final raw = d['lineas'] is List ? d['lineas'] as List : const [];
    final lines = [for (final l in raw) ?PurchaseLine.tryParse(l)];
    return Purchase(
      id: id,
      supplierId: (d['proveedorId'] as String?) ?? '',
      supplierName: (d['proveedorNombre'] as String?) ?? '',
      lines: lines,
      invalidLines: raw.length - lines.length + (raw.isEmpty ? 1 : 0),
      status:
          PurchaseStatus.values.asNameMap()[d['estado']] ??
          PurchaseStatus.cancelada,
      byName: (d['creadoPorNombre'] as String?) ?? '',
      createdBy: d['creadoPor'] as String?,
      at: toDateOrNull(d['creadoEn']),
      receivedAt: toDateOrNull(d['recibidoEn']),
      cancelReason: d['motivoCancelacion'] as String?,
    );
  }
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.supplyId,
    required this.name,
    required this.qty,
  });
  final String supplyId;
  final String name;
  final int qty;

  /// Ingrediente mal formado (documento alterado): null.
  static RecipeIngredient? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['insumoId'];
    final name = raw['nombre'];
    final qty = raw['cantidad'];
    if (id is! String || name is! String || qty is! int || qty <= 0)
      return null;
    return RecipeIngredient(supplyId: id, name: name, qty: qty);
  }

  Map<String, dynamic> toMap() => {
    'insumoId': supplyId,
    'nombre': name,
    'cantidad': qty,
  };
}

/// Receta de un plato (por porción) y su costo con el costo vigente de cada
/// insumo. Un insumo que ya no existe cuenta como costo 0 y se marca.
class Recipe {
  const Recipe(this.dishId, this.ingredients);
  final String dishId;
  final List<RecipeIngredient> ingredients;

  factory Recipe.fromMap(String id, Map<String, dynamic> d) => Recipe(id, [
    for (final i
        in (d['ingredientes'] is List ? d['ingredientes'] as List : const []))
      ?RecipeIngredient.tryParse(i),
  ]);

  int cost(Map<String, Supply> supplies) => ingredients.fold(
    0,
    (sum, i) => sum + Qty.cost(i.qty, supplies[i.supplyId]?.unitCost ?? 0),
  );

  bool hasMissing(Map<String, Supply> supplies) =>
      ingredients.any((i) => !supplies.containsKey(i.supplyId));

  /// Margen sobre el precio de venta (centavos); null si no hay precio.
  static int margin(int priceCents, int costCents) => priceCents - costCents;
}
