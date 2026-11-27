import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/users/models/app_user.dart';
import 'package:granja_azul/features/utensils/controllers/utensil_providers.dart';
import 'package:granja_azul/features/utensils/models/utensil_models.dart';
import 'package:granja_azul/features/utensils/repositories/utensil_repository.dart';
import 'package:granja_azul/features/utensils/screens/utensils_screen.dart';
import 'package:granja_azul/features/utensils/services/utensil_service.dart';
import 'package:rxdart/rxdart.dart';

import '../support/fakes.dart';

class FakeUtensilRepository implements UtensilRepository {
  final utensils = BehaviorSubject<List<Utensil>>.seeded([]);
  final assignments = BehaviorSubject<List<UtensilAssignment>>.seeded([]);
  final costs = BehaviorSubject<Map<String, int>>.seeded({});
  final moves = <(String, UtensilKind, int, String, String?, int)>[];
  final saved = <(String?, String, int, bool, int?)>[];
  var costsListened = false;

  @override
  Stream<List<Utensil>> watchUtensils() => utensils.stream;
  @override
  Stream<List<UtensilAssignment>> watchAssignments() => assignments.stream;
  @override
  Stream<List<UtensilMovement>> watchMovements() => Stream.value(const []);
  final waiters = BehaviorSubject<List<WaiterRef>>.seeded([]);
  final synced = <List<WaiterRef>>[];
  @override
  Stream<List<WaiterRef>> watchWaiters() => waiters.stream;
  @override
  Future<int> syncWaiterDirectory(List<WaiterRef> staff) async {
    synced.add(staff);
    return 0;
  }
  @override
  Stream<Map<String, int>> watchCosts() {
    costsListened = true;
    return costs.stream;
  }

  @override
  Future<void> saveUtensil(
    AppUser actor, {
    String? id,
    required String name,
    required int minStock,
    required bool active,
    int? newUnitCost,
  }) async => saved.add((id, name, minStock, active, newUnitCost));

  @override
  Future<void> registerMovement(
    AppUser actor, {
    required String utensilId,
    required UtensilKind kind,
    required int quantity,
    required String reason,
    WaiterRef? waiter,
    int sign = 1,
  }) async => moves.add((utensilId, kind, quantity, reason, waiter?.uid, sign));
}

Utensil utensil({
  int available = 10,
  int inUse = 2,
  int min = 3,
  bool active = true,
  int version = 0,
}) => Utensil(
  id: 'u1',
  name: 'Bandeja',
  available: available,
  inUse: inUse,
  minStock: min,
  active: active,
  costVersion: version,
);

void main() {
  late FakeUtensilRepository repo;
  late UtensilService service;
  final waiter = buildUser(uid: 'w1', role: UserRole.mesero);
  final admin = buildUser(uid: 'a1', role: UserRole.admin);
  const target = WaiterRef('w2', 'Rosa Díaz');

  setUp(() {
    repo = FakeUtensilRepository();
    service = UtensilService(repo);
  });

  group('permisos', () {
    test('Mesero, Admin y Superadmin ven utensilios; Cocina y Cajero no', () {
      const p = PermissionService();
      for (final role in UserRole.values) {
        final admins = role == UserRole.admin || role == UserRole.superadmin;
        expect(
          p.canDo(role, AppModule.utensils, PermissionAction.read),
          admins || role == UserRole.mesero,
          reason: role.name,
        );
        expect(
          p.canDo(role, AppModule.utensils, PermissionAction.update),
          admins,
          reason: 'update ${role.name}',
        );
        // Costos y valoración: solo la administración.
        expect(
          p.canDo(role, AppModule.utensils, PermissionAction.special),
          admins,
          reason: 'costos ${role.name}',
        );
      }
      expect(p.can(UserRole.mesero, Permission.viewUtensilCosts), isFalse);
    });
  });

  group('movimientos', () {
    test(
      'Mesero registra entregas, devoluciones, pérdidas, daños y deterioros',
      () async {
        await service.register(
          waiter,
          utensil(),
          UtensilKind.entrega,
          2,
          '',
          waiter: target,
        );
        await service.register(
          waiter,
          utensil(),
          UtensilKind.devolucion,
          1,
          '',
          waiter: target,
        );
        for (final k in [
          UtensilKind.perdida,
          UtensilKind.dano,
          UtensilKind.deterioro,
        ]) {
          await service.register(
            waiter,
            utensil(),
            k,
            1,
            'Se cayó',
            waiter: target,
          );
        }
        expect(repo.moves.map((m) => m.$2), [
          UtensilKind.entrega,
          UtensilKind.devolucion,
          UtensilKind.perdida,
          UtensilKind.dano,
          UtensilKind.deterioro,
        ]);
        expect(repo.moves.every((m) => m.$5 == 'w2'), isTrue);
      },
    );

    test('Mesero no da altas ni ajustes; Admin sí', () async {
      for (final k in [UtensilKind.alta, UtensilKind.ajuste]) {
        await expectLater(
          service.register(waiter, utensil(), k, 1, 'Conteo'),
          throwsA(isA<AppFailure>()),
        );
      }
      expect(repo.moves, isEmpty);
      await service.register(admin, utensil(), UtensilKind.alta, 5, '');
      await service.register(
        admin,
        utensil(),
        UtensilKind.ajuste,
        2,
        'Conteo',
        increase: false,
      );
      expect(repo.moves.map((m) => (m.$2, m.$6)), [
        (UtensilKind.alta, 1),
        (UtensilKind.ajuste, -1),
      ]);
    });

    test(
      'la entrega y la baja exigen un mesero; alta y ajuste no lo llevan',
      () async {
        await expectLater(
          service.register(waiter, utensil(), UtensilKind.entrega, 1, ''),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.register(
            admin,
            utensil(),
            UtensilKind.alta,
            1,
            '',
            waiter: target,
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test(
      'sin stock negativo: no se entrega ni se resta más de lo disponible',
      () async {
        await expectLater(
          service.register(
            waiter,
            utensil(available: 2),
            UtensilKind.entrega,
            3,
            '',
            waiter: target,
          ),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.register(
            admin,
            utensil(available: 2),
            UtensilKind.ajuste,
            3,
            'Conteo',
            increase: false,
          ),
          throwsA(isA<AppFailure>()),
        );
        expect(repo.moves, isEmpty);
      },
    );

    test('cantidad, motivo y utensilio activo', () async {
      for (final q in [0, -1, UtensilValidation.maxQuantity + 1]) {
        await expectLater(
          service.register(
            waiter,
            utensil(),
            UtensilKind.entrega,
            q,
            '',
            waiter: target,
          ),
          throwsA(isA<AppFailure>()),
        );
      }
      for (final r in ['', '  ', 'ab']) {
        await expectLater(
          service.register(
            waiter,
            utensil(),
            UtensilKind.perdida,
            1,
            r,
            waiter: target,
          ),
          throwsA(isA<AppFailure>()),
        );
      }
      await expectLater(
        service.register(
          waiter,
          utensil(active: false),
          UtensilKind.entrega,
          1,
          '',
          waiter: target,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(UtensilValidation.quantity('3'), 3);
      expect(UtensilValidation.quantity('1.5'), isNull);
      expect(UtensilValidation.quantity('0'), isNull);
    });
  });

  group('catálogo', () {
    test(
      'solo Admin y Superadmin lo gestionan, con nombre y montos válidos',
      () async {
        await expectLater(
          service.saveUtensil(waiter, name: 'Plato', minStock: 1, active: true),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.saveUtensil(admin, name: 'a', minStock: 1, active: true),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.saveUtensil(admin, name: 'Plato', minStock: -1, active: true),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          service.saveUtensil(
            admin,
            name: 'Plato',
            minStock: 1,
            active: true,
            newUnitCost: UtensilValidation.maxCost + 1,
          ),
          throwsA(isA<AppFailure>()),
        );
        await service.saveUtensil(
          admin,
          name: '  Plato  ',
          minStock: 4,
          active: true,
          newUnitCost: 350,
        );
        expect(repo.saved.single, (null, 'Plato', 4, true, 350));
      },
    );
  });

  group('modelos', () {
    test('stock bajo, total y lectura tolerante', () {
      expect(utensil(available: 3).isLow, isTrue);
      expect(utensil(available: 4).isLow, isFalse);
      expect(utensil(min: 0, available: 0).isLow, isFalse);
      expect(utensil(available: 4, inUse: 6).total, 10);
      expect(Utensil.tryParse('x', {'nombre': 'a'}), isNull);
      expect(UtensilMovement.tryParse('m', {'tipo': 'otro'}), isNull);
    });

    test('la valoración sale de la versión de costo del movimiento', () {
      UtensilMovement move(int version, int qty) => UtensilMovement(
        id: 'm',
        utensilId: 'u1',
        utensilName: 'Bandeja',
        kind: UtensilKind.perdida,
        quantity: qty,
        availableAfter: 0,
        inUseAfter: 0,
        reason: 'x',
        byName: 'x',
        costVersion: version,
      );
      const costs = {'u1_1': 500, 'u1_2': 800};
      expect(lossValue(move(1, 3), costs), 1500); // el costo de entonces
      expect(lossValue(move(2, 3), costs), 2400);
      expect(lossValue(move(0, 3), costs), isNull); // sin costo registrado
      expect(lossValue(move(3, 3), costs), isNull);
    });
  });

  group('pantalla', () {
    Future<void> pump(
      WidgetTester tester,
      UserRole role, {
      Size size = const Size(1100, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo.utensils.add([
        utensil(version: 1),
        utensil(available: 0).copyId('u2'),
      ]);
      repo.costs.add({'u1_1': 500});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            utensilRepositoryProvider.overrideWithValue(repo),
            sessionProvider.overrideWith(
              (ref) =>
                  Stream.value(Authenticated(buildUser(uid: 'st', role: role))),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(sessionProvider);
                  return const UtensilsScreen();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Mesero ve existencias y registra, sin catálogo, altas ni costos',
      (tester) async {
        await pump(tester, UserRole.mesero);
        expect(find.text('Bandeja'), findsNWidgets(2));
        expect(find.textContaining('Disponibles 10'), findsOneWidget);
        expect(find.text('Nuevo utensilio'), findsNothing);
        expect(find.byTooltip('Editar'), findsNothing);
        for (final k in [
          'Entrega',
          'Devolución',
          'Pérdida',
          'Daño',
          'Deterioro',
        ]) {
          expect(
            find.widgetWithText(OutlinedButton, k),
            findsWidgets,
            reason: k,
          );
        }
        expect(
          find.widgetWithText(OutlinedButton, 'Alta de stock'),
          findsNothing,
        );
        expect(find.widgetWithText(OutlinedButton, 'Ajuste'), findsNothing);
        expect(find.textContaining('S/'), findsNothing);
        // La pantalla del Mesero nunca consulta los costos.
        expect(repo.costsListened, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Mesero elige a cualquier mesero activo del directorio', (
      tester,
    ) async {
      repo.waiters.add(const [
        WaiterRef('w1', 'Ana Ríos'),
        WaiterRef('w2', 'Beto Paz'),
        WaiterRef('w3', 'Carla Inactiva', active: false),
      ]);
      await pump(tester, UserRole.mesero);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Entrega').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<WaiterRef>));
      await tester.pumpAndSettle();
      expect(find.text('Ana Ríos'), findsWidgets);
      expect(find.text('Beto Paz'), findsWidgets);
      expect(find.text('Carla Inactiva'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Admin ve el catálogo y consulta los costos', (tester) async {
      await pump(tester, UserRole.admin);
      expect(find.text('Nuevo utensilio'), findsOneWidget);
      expect(find.byTooltip('Editar'), findsNWidgets(2));
      expect(
        find.widgetWithText(OutlinedButton, 'Alta de stock'),
        findsNWidgets(2),
      );
      expect(repo.costsListened, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en celular las pestañas se recorren sin desbordes', (
      tester,
    ) async {
      await pump(tester, UserRole.mesero, size: const Size(390, 800));
      for (final t in ['Por mesero', 'Movimientos']) {
        await tester.tap(find.widgetWithText(Tab, t));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: t);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}

extension on Utensil {
  Utensil copyId(String newId) => Utensil(
    id: newId,
    name: name,
    available: available,
    inUse: inUse,
    minStock: minStock,
    active: active,
    costVersion: costVersion,
  );
}
