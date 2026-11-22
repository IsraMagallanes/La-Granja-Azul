import '../../users/models/app_user.dart';

/// Todos los montos de Caja son enteros en centavos de sol (sin errores de
/// redondeo binario). La interfaz los muestra con `soles()`.
abstract final class Money {
  /// «12», «12.5», «12,50» → centavos; null si no es un monto válido (máximo
  /// 7 enteros y 2 decimales, sin signo).
  static int? parse(String? text) {
    final t = (text ?? '').trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(t)) return null;
    final parts = t.split('.');
    final decimals = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
    return int.parse(parts[0]) * 100 + int.parse(decimals);
  }

  static String? validate(String? text, {bool allowZero = false}) {
    final cents = parse(text);
    if (cents == null) return 'Monto válido, p. ej. 12.50.';
    if (!allowZero && cents == 0) return 'Debe ser mayor que cero.';
    return null;
  }
}

enum PaymentMethod {
  efectivo('Efectivo'),
  tarjeta('Tarjeta'),
  yape('Yape'),
  plin('Plin');

  const PaymentMethod(this.label);
  final String label;
  bool get isCash => this == efectivo;
}

class Payment {
  const Payment({
    required this.orderId,
    required this.tableId,
    required this.boxId,
    required this.total,
    required this.method,
    required this.received,
    required this.change,
    required this.byName,
    this.at,
  });
  final String orderId;
  final String tableId;
  final String boxId;
  final int total;
  final PaymentMethod method;
  final int received;
  final int change;
  final String byName;
  final DateTime? at;

  factory Payment.fromMap(String id, Map<String, dynamic> d) => Payment(
    orderId: id,
    tableId: d['mesaId'] as String,
    boxId: d['cajaId'] as String,
    total: d['total'] as int,
    method: PaymentMethod.values.byName(d['metodo'] as String),
    received: d['recibido'] as int,
    change: d['vuelto'] as int,
    byName: (d['cobradoPorNombre'] as String?) ?? '',
    at: toDateOrNull(d['creadoEn']),
  );
}

enum MovementType {
  ingreso('Ingreso'),
  egreso('Egreso');

  const MovementType(this.label);
  final String label;
}

class CashMovement {
  const CashMovement({
    required this.id,
    required this.boxId,
    required this.type,
    required this.amount,
    required this.concept,
    required this.byName,
    this.at,
  });
  final String id;
  final String boxId;
  final MovementType type;
  final int amount;
  final String concept;
  final String byName;
  final DateTime? at;

  factory CashMovement.fromMap(String id, Map<String, dynamic> d) =>
      CashMovement(
        id: id,
        boxId: d['cajaId'] as String,
        type: MovementType.values.byName(d['tipo'] as String),
        amount: d['monto'] as int,
        concept: d['concepto'] as String,
        byName: (d['creadoPorNombre'] as String?) ?? '',
        at: toDateOrNull(d['creadoEn']),
      );
}

/// Una caja: desde que se abre hasta que se cierra. Los campos de cierre solo
/// existen cuando está cerrada.
class CashBox {
  const CashBox({
    required this.id,
    required this.openedBy,
    required this.openedByName,
    required this.initial,
    required this.closed,
    this.openedAt,
    this.closedByName,
    this.closedAt,
    this.expected,
    this.counted,
    this.difference,
    this.cashSales,
    this.otherSales,
    this.income,
    this.expenses,
    this.salesCount,
    this.closeNotes = '',
  });
  final String id;
  final String openedBy;
  final String openedByName;
  final int initial;
  final bool closed;
  final DateTime? openedAt;
  final String? closedByName;
  final DateTime? closedAt;
  final int? expected;
  final int? counted;
  final int? difference;
  final int? cashSales;
  final int? otherSales;
  final int? income;
  final int? expenses;
  final int? salesCount;
  final String closeNotes;

  factory CashBox.fromMap(String id, Map<String, dynamic> d) => CashBox(
    id: id,
    openedBy: d['abiertaPor'] as String,
    openedByName: (d['abiertaPorNombre'] as String?) ?? '',
    initial: d['montoInicial'] as int,
    closed: d['estado'] == 'cerrada',
    openedAt: toDateOrNull(d['abiertaEn']),
    closedByName: d['cerradaPorNombre'] as String?,
    closedAt: toDateOrNull(d['cerradaEn']),
    expected: d['esperadoEfectivo'] as int?,
    counted: d['montoContado'] as int?,
    difference: d['diferencia'] as int?,
    cashSales: d['ventasEfectivo'] as int?,
    otherSales: d['ventasOtros'] as int?,
    income: d['ingresos'] as int?,
    expenses: d['egresos'] as int?,
    salesCount: d['cantidadVentas'] as int?,
    closeNotes: (d['notasCierre'] as String?) ?? '',
  );
}

/// Totales de una caja a partir de sus pagos y movimientos. El efectivo
/// esperado es lo que debería haber en el cajón: fondo inicial + ventas en
/// efectivo (ya sin vuelto) + ingresos − egresos.
class CashSummary {
  const CashSummary({
    required this.initial,
    required this.cashSales,
    required this.otherSales,
    required this.income,
    required this.expenses,
    required this.salesCount,
    required this.byMethod,
  });

  final int initial;
  final int cashSales;
  final int otherSales;
  final int income;
  final int expenses;
  final int salesCount;
  final Map<PaymentMethod, int> byMethod;

  int get totalSales => cashSales + otherSales;
  int get expectedCash => initial + cashSales + income - expenses;

  factory CashSummary.from({
    required int initial,
    required Iterable<Payment> payments,
    required Iterable<CashMovement> movements,
  }) {
    final byMethod = {for (final m in PaymentMethod.values) m: 0};
    var count = 0;
    for (final p in payments) {
      byMethod[p.method] = byMethod[p.method]! + p.total;
      count++;
    }
    final cash = byMethod[PaymentMethod.efectivo]!;
    final all = byMethod.values.fold(0, (a, b) => a + b);
    int sum(MovementType t) =>
        movements.where((m) => m.type == t).fold(0, (a, m) => a + m.amount);
    return CashSummary(
      initial: initial,
      cashSales: cash,
      otherSales: all - cash,
      income: sum(MovementType.ingreso),
      expenses: sum(MovementType.egreso),
      salesCount: count,
      byMethod: byMethod,
    );
  }
}
