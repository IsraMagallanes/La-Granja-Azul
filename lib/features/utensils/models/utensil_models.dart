import '../../users/models/app_user.dart';

/// Tipos de movimiento de utensilios. `toWaiter`: afectan a lo que un mesero
/// concreto tiene en uso; `adminOnly`: solo Admin y Superadmin.
enum UtensilKind {
  entrega('Entrega', toWaiter: true),
  devolucion('Devolución', toWaiter: true),
  perdida('Pérdida', toWaiter: true),
  dano('Daño', toWaiter: true),
  deterioro('Deterioro', toWaiter: true),
  alta('Alta de stock', adminOnly: true),
  ajuste('Ajuste', adminOnly: true);

  const UtensilKind(
    this.label, {
    this.toWaiter = false,
    this.adminOnly = false,
  });
  final String label;
  final bool toWaiter;
  final bool adminOnly;

  /// Pérdida, daño y deterioro reducen el total (lo en uso del mesero baja).
  bool get isLoss => this == perdida || this == dano || this == deterioro;

  /// Pérdidas, daños, deterioros y ajustes exigen motivo.
  bool get needsReason => isLoss || this == ajuste;
}

/// Utensilio del catálogo. Sin importes: el costo vive en `costosUtensilios`
/// (solo Admin); aquí solo está el número de versión vigente.
class Utensil {
  const Utensil({
    required this.id,
    required this.name,
    required this.available,
    required this.inUse,
    required this.minStock,
    required this.active,
    required this.costVersion,
  });
  final String id;
  final String name;
  final int available;
  final int inUse;
  final int minStock;
  final bool active;

  /// 0 = sin costo registrado.
  final int costVersion;

  int get total => available + inUse;
  bool get isLow => active && minStock > 0 && available <= minStock;

  static Utensil? tryParse(String id, Map<String, dynamic> d) {
    final name = d['nombre'];
    final available = d['disponible'];
    final inUse = d['enUso'];
    final minStock = d['stockMinimo'];
    final active = d['activo'];
    if (name is! String ||
        available is! int ||
        inUse is! int ||
        minStock is! int ||
        active is! bool) {
      return null;
    }
    return Utensil(
      id: id,
      name: name,
      available: available,
      inUse: inUse,
      minStock: minStock,
      active: active,
      costVersion: (d['versionCosto'] as int?) ?? 0,
    );
  }
}

/// Lo que un mesero tiene en uso de un utensilio.
class UtensilAssignment {
  const UtensilAssignment({
    required this.utensilId,
    required this.waiterId,
    required this.waiterName,
    required this.quantity,
  });
  final String utensilId;
  final String waiterId;
  final String waiterName;
  final int quantity;

  static String idFor(String utensilId, String waiterId) =>
      '${utensilId}_$waiterId';

  static UtensilAssignment? tryParse(Map<String, dynamic> d) {
    final u = d['utensilioId'];
    final w = d['meseroId'];
    final n = d['meseroNombre'];
    final q = d['cantidad'];
    if (u is! String || w is! String || n is! String || q is! int) return null;
    return UtensilAssignment(
      utensilId: u,
      waiterId: w,
      waiterName: n,
      quantity: q,
    );
  }
}

/// Movimiento inmutable. Sin importes: guarda la versión de costo vigente para
/// que la administración calcule el valor sin que el mesero lo vea.
class UtensilMovement {
  const UtensilMovement({
    required this.id,
    required this.utensilId,
    required this.utensilName,
    required this.kind,
    required this.quantity,
    required this.availableAfter,
    required this.inUseAfter,
    required this.reason,
    required this.byName,
    required this.costVersion,
    this.waiterId,
    this.waiterName,
    this.at,
  });
  final String id;
  final String utensilId;
  final String utensilName;
  final UtensilKind kind;
  final int quantity;
  final int availableAfter;
  final int inUseAfter;
  final String reason;
  final String byName;
  final int costVersion;
  final String? waiterId;
  final String? waiterName;
  final DateTime? at;

  static UtensilMovement? tryParse(String id, Map<String, dynamic> d) {
    final kind = UtensilKind.values.asNameMap()[d['tipo']];
    final qty = d['cantidad'];
    if (kind == null || qty is! int || d['utensilioId'] is! String) return null;
    return UtensilMovement(
      id: id,
      utensilId: d['utensilioId'] as String,
      utensilName: (d['utensilioNombre'] as String?) ?? '',
      kind: kind,
      quantity: qty,
      availableAfter: (d['disponibleResultante'] as int?) ?? 0,
      inUseAfter: (d['enUsoResultante'] as int?) ?? 0,
      reason: (d['motivo'] as String?) ?? '',
      byName: (d['creadoPorNombre'] as String?) ?? '',
      costVersion: (d['versionCosto'] as int?) ?? 0,
      waiterId: d['meseroId'] as String?,
      waiterName: d['meseroNombre'] as String?,
      at: toDateOrNull(d['creadoEn']),
    );
  }
}

/// Un mesero al que se puede entregar un utensilio.
class WaiterRef {
  const WaiterRef(this.uid, this.name, {this.active = true});
  final String uid;
  final String name;
  final bool active;
}

/// Valor de una pérdida con el costo de la versión vigente en ese momento;
/// null si no había costo registrado. Solo la administración lo calcula, con
/// los costos de `costosUtensilios` (clave `{utensilio}_{versión}`).
int? lossValue(UtensilMovement m, Map<String, int> costsByVersionKey) {
  if (m.costVersion == 0) return null;
  final cost = costsByVersionKey['${m.utensilId}_${m.costVersion}'];
  return cost == null || cost == 0 ? null : cost * m.quantity;
}
