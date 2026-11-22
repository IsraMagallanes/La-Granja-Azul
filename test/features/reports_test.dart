import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/time/lima_time.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/cashier/models/cash_models.dart';
import 'package:granja_azul/features/inventory/controllers/inventory_providers.dart';
import 'package:granja_azul/features/inventory/models/inventory_models.dart';
import 'package:granja_azul/features/orders/models/order_item.dart';
import 'package:granja_azul/features/reports/controllers/report_providers.dart';
import 'package:granja_azul/features/reports/models/report_models.dart';
import 'package:granja_azul/features/reports/repositories/reports_repository.dart';
import 'package:granja_azul/features/reports/screens/reports_screen.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/staff/controllers/staff_providers.dart';
import 'package:granja_azul/features/staff/models/staff_member.dart';

// 2026-11-19 15:00 Lima (= 20:00 UTC), jueves.
final now = DateTime.utc(2026, 11, 19, 20);

Payment pay(
  String id,
  int total, {
  PaymentMethod method = PaymentMethod.efectivo,
  String by = 'Caja Ana',
  DateTime? at,
}) => Payment(
  orderId: id,
  tableId: '1',
  boxId: 'c1',
  total: total,
  method: method,
  received: total,
  change: 0,
  byName: by,
  at: at ?? now,
);

class FakeReportsRepository implements ReportsRepository {
  List<Payment> paymentList = [];
  List<OrderItem> itemList = [];
  List<String> itemsAskedFor = [];
  int paymentCalls = 0;
  @override
  Future<List<Payment>> payments(DateTime from, DateTime to) async {
    paymentCalls++;
    return [
      for (final p in paymentList)
        if (!p.at!.isBefore(from) && p.at!.isBefore(to)) p,
    ];
  }

  @override
  Future<List<OrderItem>> soldItems(List<String> orderIds) async {
    itemsAskedFor = orderIds;
    return itemList;
  }

  @override
  Future<List<Purchase>> receivedPurchases(DateTime from, DateTime to) async =>
      [];
  @override
  Future<List<StockMovement>> stockMovements(
    DateTime from,
    DateTime to,
  ) async => [];
}

void main() {
  group('periodos', () {
    test('hoy, 7 y 30 días y mes actual se miden en días de Lima', () {
      final today = LimaTime.startOfDay(now);
      final tomorrow = today.add(const Duration(days: 1));
      expect(ReportPeriod.today.range(now), (from: today, to: tomorrow));
      expect(
        ReportPeriod.week.range(now).from,
        today.subtract(const Duration(days: 6)),
      );
      expect(
        ReportPeriod.month30.range(now).from,
        today.subtract(const Duration(days: 29)),
      );
      expect(
        ReportPeriod.thisMonth.range(now).from,
        LimaTime.instant(2026, 11, 1),
      );
      expect(ReportPeriod.thisMonth.range(now).to, tomorrow);
    });

    test('a las 23:30 de Lima «hoy» sigue siendo ese día (ya es el día siguiente en UTC)', () {
      final late = DateTime.utc(2026, 11, 20, 4, 30); // 23:30 del 19 en Lima
      expect(
        ReportPeriod.today.range(late).from,
        LimaTime.instant(2026, 11, 19),
      );
    });
  });

  group('ventas', () {
    test('totales, promedio, métodos, cajeros, días y hora pico', () {
      final r = ReportPeriod.week.range(now);
      final sales = SalesReport.build(
        [
          pay('a', 5100),
          pay('b', 3000, method: PaymentMethod.yape, by: 'Caja Luis'),
          pay(
            'c',
            2000,
            method: PaymentMethod.tarjeta,
            at: now.subtract(const Duration(days: 2)),
          ),
          pay('d', 900, at: now.subtract(const Duration(days: 1, hours: 1))),
        ],
        from: r.from,
        to: r.to,
      );
      expect(sales.total, 11000);
      expect(sales.count, 4);
      expect(sales.average, 2750);
      expect(sales.cash, 6000);
      expect(sales.byMethod[PaymentMethod.yape], 3000);
      expect(sales.byDay, hasLength(7));
      expect(sales.byDay.last.total, 8100); // hoy
      expect(sales.bestDay!.dateKey, '2026-11-19');
      expect(sales.byCashier.first.name, 'Caja Ana');
      expect(sales.byCashier.first.total, 8000);
      expect(sales.peakHour, 15);
    });

    test('sin ventas todo es cero y no hay hora pico', () {
      final r = ReportPeriod.today.range(now);
      final sales = SalesReport.build(const [], from: r.from, to: r.to);
      expect(sales.total, 0);
      expect(sales.average, 0);
      expect(sales.peakHour, isNull);
      expect(sales.bestDay, isNull);
    });
  });

  group('platos', () {
    const pollo = Supply(
      id: 'i1',
      name: 'Pollo',
      unit: SupplyUnit.kg,
      stock: 0,
      minStock: 0,
      unitCost: 1200,
      active: true,
    );
    OrderItem item(String id, String name, double price, int q) =>
        OrderItem(dishId: id, name: name, price: price, quantity: q, notes: '');

    test('ordena por cantidad y calcula costo y margen solo con receta', () {
      final report = DishReport.build(
        [
          item('d1', 'Brasa', 25.5, 2),
          item('d1', 'Brasa', 25.5, 1),
          item('d2', 'Chicha', 6, 5),
          item('d3', 'Postre', 9, 1),
        ],
        orders: 3,
        truncated: false,
        recipes: {
          'd1': Recipe('d1', const [
            RecipeIngredient(supplyId: 'i1', name: 'Pollo', qty: 500),
          ]),
        },
        supplies: {'i1': pollo},
      );
      expect(report.rows.map((r) => r.name), ['Chicha', 'Brasa', 'Postre']);
      final brasa = report.rows[1];
      expect(brasa.quantity, 3);
      expect(brasa.revenue, 7650);
      expect(brasa.cost, 1800); // 0.5 kg × S/ 12 × 3
      expect(brasa.margin, 5850);
      expect(report.rows[0].cost, isNull);
      expect(report.units, 9);
      expect(report.withoutRecipe, 2);
      expect(report.coveredRevenue, 7650);
      expect(report.coveredCost, 1800);
    });
  });

  group('asistencia', () {
    test(
      'agrupa por persona: jornadas, horas cerradas, abiertas y regularizadas',
      () {
        final t = DateTime.utc(2026, 11, 19, 13);
        final summary = AttendanceSummary.build([
          AttendanceRecord(
            id: '1',
            uid: 'u1',
            entrada: t,
            salida: t.add(const Duration(hours: 8)),
          ),
          AttendanceRecord(
            id: '2',
            uid: 'u1',
            entrada: t.add(const Duration(days: 1)),
            salida: t.add(const Duration(days: 1, hours: 4)),
            regularizada: true,
          ),
          AttendanceRecord(id: '3', uid: 'u2', entrada: t),
        ], const []);
        final u1 = summary.workers.first;
        expect(u1.uid, 'u1');
        expect(u1.shifts, 2);
        expect(u1.hours, 12);
        expect(u1.regularized, 1);
        final u2 = summary.workers.last;
        expect(u2.open, 1);
        expect(u2.minutes, 0);
        expect(u2.name, 'Personal retirado');
        expect(summary.shifts, 3);
      },
    );
  });

  group('inventario', () {
    test('valor del stock, stock bajo, compras y mermas del periodo', () {
      const a = Supply(
        id: 'a',
        name: 'Pollo',
        unit: SupplyUnit.kg,
        stock: 10000,
        minStock: 2000,
        unitCost: 1200,
        active: true,
      );
      const b = Supply(
        id: 'b',
        name: 'Papa',
        unit: SupplyUnit.kg,
        stock: 1000,
        minStock: 2000,
        unitCost: 300,
        active: true,
      );
      const off = Supply(
        id: 'c',
        name: 'Viejo',
        unit: SupplyUnit.und,
        stock: 5000,
        minStock: 0,
        unitCost: 100,
        active: false,
      );
      final report = InventoryReport.build(
        supplies: [a, b, off],
        receivedPurchases: [
          const Purchase(
            id: 'p',
            supplierId: 's',
            supplierName: 'S',
            lines: [
              PurchaseLine(supplyId: 'a', name: 'A', qty: 4000, unitCost: 1250),
            ],
            status: PurchaseStatus.recibida,
            byName: 'x',
          ),
        ],
        movements: [
          const StockMovement(
            id: 'm1',
            supplyId: 'a',
            supplyName: 'Pollo',
            kind: MovementKind.merma,
            delta: -500,
            resulting: 9500,
            reason: 'x',
            byName: 'x',
          ),
          const StockMovement(
            id: 'm2',
            supplyId: 'a',
            supplyName: 'Pollo',
            kind: MovementKind.entrada,
            delta: 1000,
            resulting: 10500,
            reason: '',
            byName: 'x',
          ),
        ],
      );
      expect(report.valuation, 12000 + 300); // el inactivo no cuenta
      expect(report.low.map((s) => s.id), ['b']);
      expect(report.purchased, 5000);
      expect(report.purchases, 1);
      expect(report.wasteCount, 1);
      expect(report.wasteCost, 600);
      expect(report.movementsByKind[MovementKind.entrada], 1);
    });
  });

  group('permisos', () {
    test('solo Admin y Superadmin ven reportes', () {
      const permissions = PermissionService();
      for (final role in UserRole.values) {
        final allowed = role == UserRole.admin || role == UserRole.superadmin;
        expect(
          permissions.can(role, Permission.viewReports),
          allowed,
          reason: role.name,
        );
        expect(
          permissions.canDo(role, AppModule.reports, PermissionAction.create),
          isFalse,
        );
        expect(
          permissions.canDo(role, AppModule.reports, PermissionAction.update),
          isFalse,
        );
      }
    });
  });

  group('pantalla', () {
    late FakeReportsRepository repo;
    setUp(() => repo = FakeReportsRepository());

    Future<void> pump(
      WidgetTester tester, {
      Size size = const Size(1100, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsRepositoryProvider.overrideWithValue(repo),
            attendanceSummaryProvider.overrideWith(
              (ref, period) => Stream.value(const AttendanceSummary([])),
            ),
            staffListProvider.overrideWith(
              (ref) => Stream.value(const <StaffMember>[]),
            ),
            suppliesProvider.overrideWith(
              (ref) => Stream.value(const <Supply>[]),
            ),
            recipesProvider.overrideWith(
              (ref) => Stream.value(const <Recipe>[]),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ventas de hoy y cambio de periodo', (tester) async {
      final today = DateTime.now();
      repo.paymentList = [
        pay('a', 5100, at: today),
        pay('b', 3000, method: PaymentMethod.yape, at: today),
      ];
      await pump(tester);
      expect(find.text('S/ 81.00'), findsWidgets);
      expect(find.text('Por método de pago'), findsOneWidget);
      await tester.tap(find.text('Últimos 7 días'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Últimos 7 días'), findsWidgets);
      expect(repo.paymentCalls, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin ventas muestra el estado vacío', (tester) async {
      await pump(tester);
      expect(find.text('No hay ventas en este periodo.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('platos solo se calcula al pedirlo y limita las lecturas', (
      tester,
    ) async {
      final today = DateTime.now();
      repo.paymentList = [
        for (var i = 0; i < 305; i++)
          pay('o$i', 1000, at: today.subtract(Duration(seconds: i))),
      ];
      repo.itemList = const [
        OrderItem(
          dishId: 'd1',
          name: 'Brasa',
          price: 25,
          quantity: 2,
          notes: '',
        ),
      ];
      await pump(tester);
      await tester.tap(find.text('Platos'));
      await tester.pumpAndSettle();
      expect(repo.itemsAskedFor, isEmpty); // aún no se pidió
      await tester.tap(find.text('Analizar platos vendidos'));
      await tester.pumpAndSettle();
      expect(repo.itemsAskedFor, hasLength(maxDishOrders));
      expect(find.text('Brasa'), findsOneWidget);
      expect(find.textContaining('300 pedidos más recientes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en celular recorre las cuatro pestañas sin desbordes', (
      tester,
    ) async {
      await pump(tester, size: const Size(390, 800));
      for (final t in ['Platos', 'Asistencia', 'Inventario', 'Ventas']) {
        await tester.tap(find.text(t));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: t);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
