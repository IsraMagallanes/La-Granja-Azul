import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attendance/controllers/attendance_providers.dart';
import '../../inventory/controllers/inventory_providers.dart';
import '../../staff/controllers/staff_providers.dart';
import '../models/report_models.dart';
import '../repositories/reports_repository.dart';

/// Pedidos máximos que se analizan para «Platos»: cada uno cuesta una lectura
/// de sus detalles (cuota diaria de Spark).
const maxDishOrders = 300;

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => throw UnimplementedError('reportsRepositoryProvider sin override'),
);

final salesReportProvider = FutureProvider.autoDispose
    .family<SalesReport, ReportPeriod>((ref, period) async {
      final r = period.range(DateTime.now());
      final payments = await ref
          .watch(reportsRepositoryProvider)
          .payments(r.from, r.to);
      return SalesReport.build(payments, from: r.from, to: r.to);
    }, retry: (_, _) => null);

/// Platos vendidos: se calcula solo cuando se pide (lee los detalles de cada
/// pedido cobrado del periodo).
final dishReportProvider = FutureProvider.autoDispose
    .family<DishReport, ReportPeriod>((ref, period) async {
      final repository = ref.watch(reportsRepositoryProvider);
      final r = period.range(DateTime.now());
      final payments = await repository.payments(r.from, r.to)
        ..sort(
          (a, b) => (b.at ?? DateTime(1970)).compareTo(a.at ?? DateTime(1970)),
        );
      final used = payments.take(maxDishOrders).toList();
      final items = await repository.soldItems([
        for (final p in used) p.orderId,
      ]);
      final recipes = await ref.watch(recipesProvider.future);
      // Reportes: solo Admin/Superadmin, únicos que leen los costos.
      final costs = await ref.watch(supplyCostsProvider.future);
      return DishReport.build(
        items,
        orders: used.length,
        truncated: payments.length > maxDishOrders,
        recipes: {for (final x in recipes) x.dishId: x},
        costs: costs,
      );
    }, retry: (_, _) => null);

final attendanceSummaryProvider = StreamProvider.autoDispose
    .family<AttendanceSummary, ReportPeriod>((ref, period) {
      final r = period.range(DateTime.now());
      final staff = ref.watch(staffListProvider).value ?? const [];
      return ref
          .watch(attendanceAdminRepositoryProvider)
          .watchRange(r.from, r.to)
          .map((records) => AttendanceSummary.build(records, staff));
    }, retry: (_, _) => null);

final inventoryReportProvider = FutureProvider.autoDispose
    .family<InventoryReport, ReportPeriod>((ref, period) async {
      final repository = ref.watch(reportsRepositoryProvider);
      final r = period.range(DateTime.now());
      final purchases = await repository.receivedPurchases(r.from, r.to);
      final movements = await repository.stockMovements(r.from, r.to);
      final supplies = await ref.watch(suppliesProvider.future);
      final costs = await ref.watch(supplyCostsProvider.future);
      return InventoryReport.build(
        supplies: supplies,
        costs: costs,
        receivedPurchases: purchases,
        movements: movements,
      );
    }, retry: (_, _) => null);
