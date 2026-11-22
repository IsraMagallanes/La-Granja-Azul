import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/controllers/auth_providers.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/orders/controllers/order_providers.dart';
import 'package:granja_azul/features/reservations/controllers/reservation_providers.dart';
import 'package:granja_azul/features/reservations/models/reservation.dart';
import 'package:granja_azul/features/reservations/repositories/reservation_repository.dart';
import 'package:granja_azul/features/reservations/screens/reservations_screen.dart';
import 'package:granja_azul/features/reservations/services/reservation_service.dart';
import 'package:granja_azul/features/reservations/widgets/reservation_editor.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/tables/controllers/table_providers.dart';
import 'package:granja_azul/features/tables/models/restaurant_table.dart';
import 'package:granja_azul/features/tables/screens/tables_screen.dart';

import '../support/fakes.dart';
import '../support/order_fakes.dart';

class FakeReservationRepository implements ReservationRepository {
  final reservations = StreamController<List<Reservation>>.broadcast();
  final calls = <String>[];
  ReservationDraft? lastDraft;
  bool? lastConfirmed;
  String? lastReason;
  Object? failSeat;

  @override
  Stream<List<Reservation>> watchReservations() => reservations.stream;
  @override
  Future<void> create(
    ReservationDraft draft, {
    required String actorUid,
    required String actorName,
  }) async {
    calls.add('create:$actorUid:$actorName');
    lastDraft = draft;
  }

  @override
  Future<void> edit(
    String id,
    ReservationDraft draft, {
    required bool confirmed,
  }) async {
    calls.add('edit:$id');
    lastDraft = draft;
    lastConfirmed = confirmed;
  }

  @override
  Future<void> confirm(String id) async => calls.add('confirm:$id');
  @override
  Future<void> cancel(String id, String reason) async {
    calls.add('cancel:$id');
    lastReason = reason;
  }

  @override
  Future<void> markNoShow(String id) async => calls.add('noShow:$id');
  @override
  Future<void> seat(String id, String orderId) async {
    if (failSeat != null) throw failSeat!;
    calls.add('seat:$id:$orderId');
  }
}

const _t4 = RestaurantTable(id: '4', capacity: 4, active: true);
const _t2 = RestaurantTable(id: '2', capacity: 2, active: true);
const _off = RestaurantTable(id: '9', capacity: 8, active: false);

/// Mañana a las 13:00 de Lima (UTC-5), fijo respecto de [now].
final _now = DateTime.utc(2026, 11, 19, 15); // 10:00 Lima
final _noon = DateTime.utc(2026, 11, 19, 18); // 13:00 Lima, hoy

Reservation _res({
  String id = 'r1',
  String table = '4',
  DateTime? at,
  ReservationStatus status = ReservationStatus.pendiente,
  String? cancelReason,
  String? orderId,
}) => Reservation(
  id: id,
  tableId: table,
  customer: 'Rosa Díaz',
  phone: '987654321',
  partySize: 3,
  at: at ?? _noon,
  status: status,
  notes: '',
  createdByName: 'Ana',
  cancelReason: cancelReason,
  orderId: orderId,
);

ReservationDraft _draft({
  String table = '4',
  String customer = 'Rosa Díaz',
  String phone = '987654321',
  int party = 3,
  DateTime? at,
  String notes = '',
}) => ReservationDraft(
  tableId: table,
  customer: customer,
  phone: phone,
  partySize: party,
  at: at ?? _noon,
  notes: notes,
);

void main() {
  group('modelo', () {
    test('lee el documento y expone su estado', () {
      final r = Reservation.fromMap('x', {
        'mesaId': '4',
        'cliente': 'Rosa',
        'telefono': '987654321',
        'personas': 3,
        'fechaHora': DateTime.utc(2026, 11, 19, 18),
        'estado': 'cancelada',
        'notas': '',
        'creadoPorNombre': 'Ana',
        'motivoCancelacion': 'Llamó',
      });
      expect(r.status, ReservationStatus.cancelada);
      expect(r.status.open, isFalse);
      expect(r.cancelReason, 'Llamó');
      expect(ReservationStatus.pendiente.open, isTrue);
      expect(ReservationStatus.confirmada.open, isTrue);
      expect(ReservationStatus.cumplida.open, isFalse);
      expect(ReservationStatus.noAsistio.open, isFalse);
    });

    test('dos horas de ocupación: choca por debajo de 2 h y no a las 2 h', () {
      final r = _res();
      expect(
        r.overlaps(_noon.add(const Duration(hours: 1, minutes: 59))),
        isTrue,
      );
      expect(
        r.overlaps(_noon.subtract(const Duration(hours: 1, minutes: 59))),
        isTrue,
      );
      expect(r.overlaps(_noon.add(const Duration(hours: 2))), isFalse);
      expect(r.overlaps(_noon.subtract(const Duration(hours: 2))), isFalse);
    });
  });

  group('servicio', () {
    late FakeReservationRepository repository;
    late FakeOrderRepository orders;
    late ReservationService service;
    final tables = [_t4, _t2, _off];

    setUp(() {
      repository = FakeReservationRepository();
      orders = FakeOrderRepository();
      service = ReservationService(repository, orders);
    });
    tearDown(() async {
      await repository.reservations.close();
      await orders.orders.close();
      await orders.items.close();
    });

    Future<void> create(
      ReservationDraft d, [
      List<Reservation> existing = const [],
    ]) => service.create(
      d,
      actorUid: 'w1',
      actorName: 'Ana',
      tables: tables,
      existing: existing,
      now: _now,
    );

    test(
      'crea con los datos recortados y la identidad de quien reserva',
      () async {
        await create(
          _draft(
            customer: '  Rosa Díaz ',
            phone: ' 987654321 ',
            notes: ' sin ají ',
          ),
        );
        expect(repository.calls, ['create:w1:Ana']);
        expect(repository.lastDraft!.customer, 'Rosa Díaz');
        expect(repository.lastDraft!.phone, '987654321');
        expect(repository.lastDraft!.notes, 'sin ají');
      },
    );

    test('rechaza datos inválidos sin llegar al repositorio', () async {
      final invalid = [
        _draft(customer: ' a '),
        _draft(phone: '12ab'),
        _draft(phone: '123'),
        _draft(party: 0),
        _draft(party: 51),
        _draft(notes: 'x' * 301),
      ];
      for (final d in invalid) {
        expect(create(d), throwsA(isA<AppFailure>()));
      }
      expect(repository.calls, isEmpty);
    });

    test('exige una mesa activa con capacidad suficiente', () async {
      await expectLater(
        create(_draft(table: '77')),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(create(_draft(table: '9')), throwsA(isA<AppFailure>()));
      await expectLater(
        create(_draft(table: '2', party: 3)),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('2 personas'),
          ),
        ),
      );
      expect(repository.calls, isEmpty);
    });

    test('exige fecha futura', () async {
      await expectLater(create(_draft(at: _now)), throwsA(isA<AppFailure>()));
      await expectLater(
        create(_draft(at: _now.subtract(const Duration(hours: 1)))),
        throwsA(isA<AppFailure>()),
      );
      expect(repository.calls, isEmpty);
    });

    test(
      'avisa el cruce de horario de la misma mesa (solo reservas abiertas)',
      () async {
        final clash = _res(at: _noon.add(const Duration(hours: 1)));
        await expectLater(
          create(_draft(), [clash]),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('14:00'),
            ),
          ),
        );
        // Otra mesa, a las 2 h justas, o una reserva ya cancelada no estorban.
        await create(_draft(table: '2', party: 2), [clash]);
        await create(_draft(), [_res(at: _noon.add(const Duration(hours: 2)))]);
        await create(_draft(), [
          _res(
            at: _noon.add(const Duration(hours: 1)),
            status: ReservationStatus.cancelada,
          ),
        ]);
        expect(repository.calls, hasLength(3));
      },
    );

    test('editar conserva «confirmada», ignora su propio horario y no toca estados finales', () async {
      final confirmed = _res(status: ReservationStatus.confirmada);
      await service.edit(
        confirmed,
        _draft(party: 2),
        tables: tables,
        existing: [confirmed],
        now: _now,
      );
      expect(repository.lastConfirmed, isTrue);
      await service.edit(
        _res(),
        _draft(),
        tables: tables,
        existing: [_res()],
        now: _now,
      );
      expect(repository.lastConfirmed, isFalse);
      await expectLater(
        service.edit(
          _res(status: ReservationStatus.cumplida),
          _draft(),
          tables: tables,
          existing: const [],
          now: _now,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('confirmar solo vale para pendientes', () async {
      await service.confirm(_res());
      expect(repository.calls, ['confirm:r1']);
      await expectLater(
        service.confirm(_res(status: ReservationStatus.confirmada)),
        throwsA(isA<AppFailure>()),
      );
    });

    test('cancelar exige motivo y una reserva abierta', () async {
      await expectLater(
        service.cancel(_res(), ' '),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.cancel(
          _res(status: ReservationStatus.noAsistio),
          'Motivo válido',
        ),
        throwsA(isA<AppFailure>()),
      );
      await service.cancel(_res(), '  Llamó para cancelar ');
      expect(repository.lastReason, 'Llamó para cancelar');
    });

    test('«No asistió» solo pasada la hora', () async {
      await expectLater(
        service.markNoShow(
          _res(),
          now: _noon.subtract(const Duration(minutes: 1)),
        ),
        throwsA(isA<AppFailure>()),
      );
      await service.markNoShow(
        _res(),
        now: _noon.add(const Duration(minutes: 30)),
      );
      expect(repository.calls, ['noShow:r1']);
    });

    test('sentar abre el pedido de la mesa y deja la reserva cumplida con su pedido', () async {
      final id = await service.seat(
        _res(status: ReservationStatus.confirmada),
        waiterUid: 'w1',
      );
      expect(id, 'order');
      expect(orders.openedTable, '4');
      expect(repository.calls, ['seat:r1:order']);
    });

    test('no se sienta una reserva pendiente ni se abre pedido', () async {
      await expectLater(
        service.seat(_res(), waiterUid: 'w1'),
        throwsA(isA<AppFailure>()),
      );
      expect(orders.openedTable, isNull);
    });

    test(
      'si el pedido se abre pero la reserva no se actualiza, lo explica',
      () async {
        repository.failSeat = Exception('red');
        await expectLater(
          service.seat(
            _res(status: ReservationStatus.confirmada),
            waiterUid: 'w1',
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Se abrió el pedido'),
            ),
          ),
        );
        expect(orders.openedTable, '4');
      },
    );
  });

  group('pantalla', () {
    late FakeReservationRepository repository;
    late FakeTableRepository tableRepo;
    late FakeOrderRepository orders;

    setUp(() {
      repository = FakeReservationRepository();
      tableRepo = FakeTableRepository()..tables.add([_t4, _t2]);
      orders = FakeOrderRepository();
    });
    tearDown(() async {
      await repository.reservations.close();
      await tableRepo.tables.close();
      await orders.orders.close();
      await orders.items.close();
    });

    Future<void> pump(
      WidgetTester tester, {
      UserRole role = UserRole.mesero,
      Widget home = const ReservationsScreen(),
    }) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reservationRepositoryProvider.overrideWithValue(repository),
            tableRepositoryProvider.overrideWithValue(tableRepo),
            orderRepositoryProvider.overrideWithValue(orders),
            sessionProvider.overrideWith(
              (ref) =>
                  Stream.value(Authenticated(buildUser(uid: 'w1', role: role))),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    void emit(List<Reservation> list) => repository.reservations.add(list);

    // La pantalla usa la hora real; se construyen reservas respecto de «ahora».
    Reservation inHours(
      int hours, {
      String id = 'r1',
      ReservationStatus status = ReservationStatus.pendiente,
      String table = '4',
    }) => _res(
      id: id,
      table: table,
      status: status,
      at: DateTime.now().add(Duration(hours: hours)),
    );

    testWidgets('vistas Hoy, Próximas e Historial', (tester) async {
      await pump(tester);
      final soon = inHours(1, id: 'a');
      final later = _res(
        id: 'b',
        at: DateTime.now().add(const Duration(days: 3)),
        status: ReservationStatus.confirmada,
      );
      final done = _res(
        id: 'c',
        at: DateTime.now().subtract(const Duration(days: 2)),
        status: ReservationStatus.cumplida,
      );
      emit([done, soon, later]);
      await tester.pump();
      await tester.pump();
      // Hoy: solo la de hoy (a la hora de Lima).
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Confirmada'), findsNothing);
      await tester.tap(find.text('Próximas'));
      await tester.pump();
      expect(find.text('Confirmada'), findsOneWidget);
      expect(find.text('Pendiente'), findsNothing);
      await tester.tap(find.text('Historial'));
      await tester.pump();
      expect(find.text('Cumplida'), findsOneWidget);
      expect(find.text('Confirmada'), findsNothing);
    });

    testWidgets('confirmar una pendiente', (tester) async {
      await pump(tester);
      emit([inHours(1)]);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['confirm:r1']);
    });

    testWidgets('cancelar pide motivo y lo envía', (tester) async {
      await pump(tester);
      emit([inHours(1)]);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar reservación'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indica el motivo (3 a 200 caracteres).'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'Llamó para cancelar');
      await tester.tap(find.text('Cancelar reservación'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['cancel:r1']);
      expect(repository.lastReason, 'Llamó para cancelar');
    });

    testWidgets(
      'confirmada: «Sentar y abrir pedido» abre el pedido de la mesa',
      (tester) async {
        await pump(tester);
        emit([inHours(1, status: ReservationStatus.confirmada)]);
        await tester.pump();
        await tester.pump();
        expect(find.text('Confirmar'), findsNothing);
        await tester.tap(find.text('Sentar y abrir pedido'));
        await tester.pump();
        await tester.pump();
        expect(orders.openedTable, '4');
        expect(repository.calls, ['seat:r1:order']);
      },
    );

    testWidgets('«No asistió» aparece solo cuando ya pasó la hora', (
      tester,
    ) async {
      await pump(tester);
      emit([inHours(1)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('No asistió'), findsNothing);
      emit([_res(at: DateTime.now().subtract(const Duration(minutes: 1)))]);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('No asistió'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['noShow:r1']);
    });

    testWidgets('el cajero solo consulta: sin botones de gestión', (
      tester,
    ) async {
      await pump(tester, role: UserRole.cajero);
      emit([inHours(1)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Nueva reservación'), findsNothing);
      expect(find.text('Confirmar'), findsNothing);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets(
      'las canceladas muestran su motivo y las cumplidas enlazan el pedido',
      (tester) async {
        await pump(tester);
        final h = DateTime.now();
        emit([
          _res(
            id: 'a',
            at: h,
            status: ReservationStatus.cancelada,
            cancelReason: 'Llamó',
          ),
          _res(
            id: 'b',
            at: h,
            status: ReservationStatus.cumplida,
            orderId: 'o9',
          ),
        ]);
        await tester.pump();
        await tester.pump();
        expect(find.text('Motivo de cancelación: Llamó'), findsOneWidget);
        expect(find.text('Ver pedido'), findsOneWidget);
      },
    );

    testWidgets('el formulario pide mesa y hora, y valida los campos', (
      tester,
    ) async {
      await pump(tester);
      emit(const []);
      await tester.pump();
      await tester.tap(find.text('Nueva reservación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.text('Elige una mesa.'), findsOneWidget);
      expect(find.text('Nombre de 2 a 80 caracteres.'), findsOneWidget);
      expect(find.text('Entre 1 y 50 personas.'), findsOneWidget);
      expect(find.byType(ReservationEditor), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    testWidgets('el mosaico de la mesa muestra su reservación de hoy', (
      tester,
    ) async {
      await pump(tester, home: const TablesScreen());
      emit([
        inHours(1),
        inHours(1, id: 'x', table: '2', status: ReservationStatus.cancelada),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Reservada'), findsOneWidget);
      expect(find.textContaining('Rosa Díaz'), findsOneWidget);
    });

    testWidgets(
      'sin permiso para leer reservaciones el mosaico de mesas sigue funcionando',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reservationRepositoryProvider.overrideWithValue(repository),
              tableRepositoryProvider.overrideWithValue(tableRepo),
              orderRepositoryProvider.overrideWithValue(orders),
              sessionProvider.overrideWith(
                (ref) => Stream.value(
                  Authenticated(buildUser(uid: 'k', role: UserRole.cajero)),
                ),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: TablesScreen())),
          ),
        );
        await tester.pump();
        await tester.pump();
        repository.reservations.addError(Exception('permission-denied'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Mesa 4'), findsOneWidget);
        expect(find.textContaining('Reservada'), findsNothing);
      },
    );
  });
}
