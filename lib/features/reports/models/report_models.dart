import '../../../core/time/lima_time.dart';
import '../../attendance/models/attendance_models.dart';
import '../../cashier/models/cash_models.dart';
import '../../inventory/models/inventory_models.dart';
import '../../orders/models/order_item.dart';
import '../../staff/models/staff_member.dart';

/// Periodos de los reportes, siempre por días de Lima. El fin es exclusivo.
enum ReportPeriod {
  today('Hoy'),
  week('Últimos 7 días'),
  month30('Últimos 30 días'),
  thisMonth('Este mes');

  const ReportPeriod(this.label);
  final String label;

  ({DateTime from, DateTime to}) range(DateTime now) {
    final today = LimaTime.startOfDay(now);
    final tomorrow = today.add(const Duration(days: 1));
    switch (this) {
      case ReportPeriod.today:
        return (from: today, to: tomorrow);
      case ReportPeriod.week:
        return (from: today.subtract(const Duration(days: 6)), to: tomorrow);
      case ReportPeriod.month30:
        return (from: today.subtract(const Duration(days: 29)), to: tomorrow);
      case ReportPeriod.thisMonth:
        final w = LimaTime.wall(now);
        return (from: LimaTime.instant(w.year, w.month, 1), to: tomorrow);
    }
  }
}

class DayTotal {
  const DayTotal(this.dateKey, this.total, this.count);
  final String dateKey;
  final int total;
  final int count;
}

class CashierTotal {
  const CashierTotal(this.name, this.total, this.count);
  final String name;
  final int total;
  final int count;
}

/// Ventas cobradas en un periodo, a partir de los pagos.
class SalesReport {
  const SalesReport({
    required this.total,
    required this.count,
    required this.byMethod,
    required this.byDay,
    required this.byCashier,
    required this.byHour,
  });

  final int total;
  final int count;
  final Map<PaymentMethod, int> byMethod;
  final List<DayTotal> byDay;
  final List<CashierTotal> byCashier;

  /// Ventas (cantidad) por hora de Lima, 0–23.
  final List<int> byHour;

  int get average => count == 0 ? 0 : (total / count).round();
  int get cash => byMethod[PaymentMethod.efectivo] ?? 0;
  DayTotal? get bestDay => byDay.isEmpty || count == 0
      ? null
      : byDay.reduce((a, b) => b.total > a.total ? b : a);
  int? get peakHour {
    if (count == 0) return null;
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (byHour[h] > byHour[best]) best = h;
    }
    return best;
  }

  factory SalesReport.build(
    Iterable<Payment> payments, {
    required DateTime from,
    required DateTime to,
  }) {
    final byMethod = {for (final m in PaymentMethod.values) m: 0};
    final days = <String, List<int>>{};
    for (
      var d = from;
      d.isBefore(to) && days.length < 62;
      d = d.add(const Duration(days: 1))
    ) {
      days[LimaTime.dateKey(d)] = [0, 0];
    }
    final cashiers = <String, List<int>>{};
    final hours = List<int>.filled(24, 0);
    var total = 0;
    var count = 0;
    for (final p in payments) {
      total += p.total;
      count++;
      byMethod[p.method] = byMethod[p.method]! + p.total;
      final c = cashiers.putIfAbsent(p.byName, () => [0, 0]);
      c[0] += p.total;
      c[1]++;
      final at = p.at;
      if (at != null) {
        final day = days[LimaTime.dateKey(at)];
        if (day != null) {
          day[0] += p.total;
          day[1]++;
        }
        hours[LimaTime.wall(at).hour]++;
      }
    }
    return SalesReport(
      total: total,
      count: count,
      byMethod: byMethod,
      byDay: [
        for (final e in days.entries) DayTotal(e.key, e.value[0], e.value[1]),
      ],
      byCashier: [
        for (final e in cashiers.entries)
          CashierTotal(e.key, e.value[0], e.value[1]),
      ]..sort((a, b) => b.total.compareTo(a.total)),
      byHour: hours,
    );
  }
}

class DishSales {
  const DishSales({
    required this.dishId,
    required this.name,
    required this.quantity,
    required this.revenue,
    this.cost,
  });
  final String dishId;
  final String name;
  final int quantity;
  final int revenue;

  /// Costo estimado con la receta vigente; null si el plato no tiene receta.
  final int? cost;
  int? get margin => cost == null ? null : revenue - cost!;
}

/// Platos vendidos (por cantidad) con su ingreso y, si hay receta, costo y
/// margen estimados con el costo vigente de los insumos.
class DishReport {
  const DishReport({
    required this.rows,
    required this.orders,
    required this.truncated,
  });
  final List<DishSales> rows;
  final int orders;

  /// Se analizaron solo los pedidos más recientes (límite de lecturas).
  final bool truncated;

  int get revenue => rows.fold(0, (a, r) => a + r.revenue);
  int get units => rows.fold(0, (a, r) => a + r.quantity);

  /// Ingreso y costo de los platos con receta (para un margen comparable).
  int get coveredRevenue =>
      rows.where((r) => r.cost != null).fold(0, (a, r) => a + r.revenue);
  int get coveredCost => rows.fold(0, (a, r) => a + (r.cost ?? 0));
  int get withoutRecipe => rows.where((r) => r.cost == null).length;

  factory DishReport.build(
    Iterable<OrderItem> items, {
    required int orders,
    required bool truncated,
    required Map<String, Recipe> recipes,
    required Map<String, int> costs,
  }) {
    final qty = <String, int>{};
    final revenue = <String, int>{};
    final names = <String, String>{};
    for (final i in items) {
      qty[i.dishId] = (qty[i.dishId] ?? 0) + i.quantity;
      revenue[i.dishId] = (revenue[i.dishId] ?? 0) + i.subtotalCents;
      names[i.dishId] = i.name;
    }
    final rows =
        [
          for (final id in qty.keys)
            DishSales(
              dishId: id,
              name: names[id]!,
              quantity: qty[id]!,
              revenue: revenue[id]!,
              cost: (recipes[id] == null || recipes[id]!.ingredients.isEmpty)
                  ? null
                  : recipes[id]!.cost(costs) * qty[id]!,
            ),
        ]..sort((a, b) {
          final byQty = b.quantity.compareTo(a.quantity);
          return byQty != 0 ? byQty : a.name.compareTo(b.name);
        });
    return DishReport(rows: rows, orders: orders, truncated: truncated);
  }
}

class WorkerAttendance {
  const WorkerAttendance({
    required this.uid,
    required this.name,
    required this.shifts,
    required this.minutes,
    required this.open,
    required this.regularized,
  });
  final String uid;
  final String name;
  final int shifts;

  /// Minutos de jornadas ya cerradas.
  final int minutes;
  final int open;
  final int regularized;
  double get hours => minutes / 60;
}

/// Horas trabajadas por persona en el periodo. Solo informa; no calcula pagos.
class AttendanceSummary {
  const AttendanceSummary(this.workers);
  final List<WorkerAttendance> workers;

  int get shifts => workers.fold(0, (a, w) => a + w.shifts);
  int get minutes => workers.fold(0, (a, w) => a + w.minutes);

  factory AttendanceSummary.build(
    Iterable<AttendanceRecord> records,
    Iterable<StaffMember> staff,
  ) {
    final names = {for (final s in staff) s.uid: s.nombreCompleto};
    final data = <String, List<int>>{};
    for (final r in records) {
      final d = data.putIfAbsent(r.uid, () => [0, 0, 0, 0]);
      d[0]++;
      final duration = r.duracion;
      if (duration != null) d[1] += duration.inMinutes;
      if (r.abierta) d[2]++;
      if (r.regularizada) d[3]++;
    }
    return AttendanceSummary(
      [
        for (final e in data.entries)
          WorkerAttendance(
            uid: e.key,
            name: names[e.key] ?? 'Personal retirado',
            shifts: e.value[0],
            minutes: e.value[1],
            open: e.value[2],
            regularized: e.value[3],
          ),
      ]..sort((a, b) => b.minutes.compareTo(a.minutes)),
    );
  }
}

/// Estado del inventario y gasto del periodo (compras recibidas y mermas).
class InventoryReport {
  const InventoryReport({
    required this.valuation,
    required this.low,
    required this.out,
    required this.purchased,
    required this.purchases,
    required this.wasteCost,
    required this.wasteCount,
    required this.movementsByKind,
  });
  final int valuation;
  final List<Supply> low;
  final int out;
  final int purchased;
  final int purchases;
  final int wasteCost;
  final int wasteCount;
  final Map<MovementKind, int> movementsByKind;

  factory InventoryReport.build({
    required Iterable<Supply> supplies,
    required Map<String, int> costs,
    required Iterable<Purchase> receivedPurchases,
    required Iterable<StockMovement> movements,
  }) {
    final active = supplies.where((s) => s.active);
    var wasteCost = 0;
    var wasteCount = 0;
    final kinds = {for (final k in MovementKind.values) k: 0};
    for (final m in movements) {
      kinds[m.kind] = kinds[m.kind]! + 1;
      if (m.kind == MovementKind.merma) {
        wasteCount++;
        wasteCost += Qty.cost(m.delta.abs(), costs[m.supplyId] ?? 0);
      }
    }
    return InventoryReport(
      valuation: active.fold(
        0,
        (a, s) => a + Qty.cost(s.stock, costs[s.id] ?? 0),
      ),
      low: [
        for (final s in active)
          if (s.isLow) s,
      ]..sort((a, b) => a.name.compareTo(b.name)),
      out: active.where((s) => s.isOut).length,
      purchased: receivedPurchases.fold(0, (a, p) => a + p.total),
      purchases: receivedPurchases.length,
      wasteCost: wasteCost,
      wasteCount: wasteCount,
      movementsByKind: kinds,
    );
  }
}
