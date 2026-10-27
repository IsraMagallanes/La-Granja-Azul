import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/core/routing/app_routes.dart';
import 'package:granja_azul/core/routing/auth_redirect.dart';
import 'package:granja_azul/core/time/lima_time.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/attendance/models/schedule.dart';
import 'package:granja_azul/features/attendance/repositories/attendance_repositories.dart';
import 'package:granja_azul/features/attendance/services/attendance_report.dart';
import 'package:granja_azul/features/attendance/services/attendance_services.dart';
import 'package:granja_azul/features/attendance/services/qr_payload.dart';
import 'package:granja_azul/features/attendance/services/regularization.dart';
import 'package:granja_azul/features/attendance/services/scan_validator.dart';
import 'package:granja_azul/features/attendance/services/terminal_binding.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/auth/services/session_resolver.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/roles/services/role_navigation.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/users/models/app_user.dart';

import '../support/fakes.dart';
import '../support/phase3_fakes.dart';

RoleNavigation nav() => const RoleNavigation(PermissionService());

QrToken tokenOf(PunchType type, {String id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90', String uid = 'w1', bool used = false}) =>
    QrToken(
      id: id,
      uid: uid,
      tipo: type,
      nombreMostrar: 'Mario',
      creadoEn: DateTime.utc(2026, 10, 26, 13),
      usadoEn: used ? DateTime.utc(2026, 10, 26, 13) : null,
    );

void main() {
  group('hora de Lima', () {
    test('Lima es UTC-5 todo el año', () {
      final utc = DateTime.utc(2026, 10, 26, 3, 30); // 22:30 del 25 en Lima
      expect(LimaTime.dateKey(utc), '2026-10-25');
      expect(LimaTime.formatTime(utc), '22:30');
      expect(LimaTime.instant(2026, 10, 25, 22, 30), utc);
    });

    test('inicio del día de Lima', () {
      expect(LimaTime.startOfDay(DateTime.utc(2026, 10, 26, 3)),
          DateTime.utc(2026, 10, 25, 5));
    });
  });

  group('contenido del QR', () {
    test('solo lleva un identificador opaco, sin datos personales', () {
      final id = QrPayload.generateId();
      final payload = QrPayload.encode(id);
      expect(payload, matches(RegExp(r'^GA1:[0-9a-f]{32}$')));
      expect(payload.length, 36);
    });

    test('ids aleatorios y no repetidos', () {
      final ids = {for (var i = 0; i < 500; i++) QrPayload.generateId()};
      expect(ids, hasLength(500));
    });

    test('decodifica solo QR de la aplicación', () {
      final id = QrPayload.generateId(Random(1));
      expect(QrPayload.decode(QrPayload.encode(id)), id);
      expect(QrPayload.decode('https://ejemplo.com'), isNull);
      expect(QrPayload.decode('GA1:corto'), isNull);
      expect(QrPayload.decode('GA1:${'Z' * 32}'), isNull);
      expect(QrPayload.decode(null), isNull);
    });

    test('vigencia de 45 s, dentro del rango de 30 a 60 s', () {
      expect(QrToken.lifetime.inSeconds, inInclusiveRange(30, 60));
    });
  });

  group('QR del trabajador', () {
    late FakeWorkerAttendanceRepository repo;
    late QrIssueService service;
    final worker = actorOf(UserRole.mesero, uid: 'w1');

    setUp(() {
      repo = FakeWorkerAttendanceRepository();
      service = QrIssueService(repo);
    });

    test('genera un QR de entrada con vencimiento y NO registra asistencia', () async {
      final now = DateTime(2026, 10, 26, 8);
      final qr = await service.issue(worker, PunchType.entrada, state: null, clock: () => now);
      expect(qr.expiresAt, now.add(const Duration(seconds: 45)));
      expect(QrPayload.decode(qr.payload), qr.token.id);
      expect(repo.tokensCreated.single.$1, PunchType.entrada);
      // El repositorio del trabajador ni siquiera puede registrar asistencia.
      expect(repo, isA<WorkerAttendanceRepository>());
      expect(repo, isNot(isA<TerminalScanRepository>()));
    });

    test('no genera entrada si ya hay una abierta', () {
      expect(
        service.issue(worker, PunchType.entrada,
            state: const AttendanceState(abierta: true, asistenciaId: 'x')),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.tokensCreated, isEmpty);
    });

    test('no genera salida sin entrada abierta', () {
      expect(service.issue(worker, PunchType.salida, state: null), throwsA(isA<AppFailure>()));
      expect(
        service.issue(worker, PunchType.salida, state: const AttendanceState(abierta: false)),
        throwsA(isA<AppFailure>()),
      );
    });

    test('genera salida con entrada abierta', () async {
      final qr = await service.issue(worker, PunchType.salida,
          state: const AttendanceState(abierta: true, asistenciaId: 'x'));
      expect(qr.token.tipo, PunchType.salida);
    });

    test('un trabajador inactivo no genera QR', () {
      const inactive = AppUser(
        uid: 'w2', email: 'w2@granja.pe', nombre: 'W', role: UserRole.mesero, activo: false);
      expect(service.issue(inactive, PunchType.entrada, state: null), throwsA(isA<AppFailure>()));
    });

    test('la solicitud de corrección exige motivo', () async {
      await expectLater(
        service.requestCorrection(worker: worker, fecha: '2026-10-20', tipo: 'entrada', motivo: 'corto'),
        throwsA(isA<AppFailure>()),
      );
      await service.requestCorrection(
          worker: worker, fecha: '2026-10-20', tipo: 'entrada', motivo: 'Olvidé marcar la entrada');
      expect(repo.corrections, hasLength(1));
    });
  });

  group('ScanValidator', () {
    const validator = ScanValidator();

    test('QR inexistente o ya usado', () {
      expect(validator.evaluate(token: null), isA<ScanRejected>());
      expect(validator.evaluate(token: tokenOf(PunchType.entrada, used: true)), isA<ScanRejected>());
    });

    test('entrada duplicada', () {
      final d = validator.evaluate(
        token: tokenOf(PunchType.entrada),
        state: const AttendanceState(abierta: true, asistenciaId: 'a'),
      );
      expect(d, isA<ScanRejected>());
    });

    test('salida sin entrada', () {
      expect(validator.evaluate(token: tokenOf(PunchType.salida), state: null), isA<ScanRejected>());
      expect(
        validator.evaluate(token: tokenOf(PunchType.salida), state: const AttendanceState(abierta: false)),
        isA<ScanRejected>(),
      );
    });

    test('entrada y salida válidas se identifican automáticamente', () {
      final entrada = validator.evaluate(token: tokenOf(PunchType.entrada), state: null);
      expect(entrada, isA<ScanProceed>());
      final salida = validator.evaluate(
        token: tokenOf(PunchType.salida),
        state: const AttendanceState(abierta: true, asistenciaId: 'rec1'),
      );
      expect((salida as ScanProceed).openRecordId, 'rec1');
    });
  });

  group('terminal', () {
    late FakeTerminalScanRepository repo;
    late TerminalScanService service;
    final entradaId = 'a' * 32;
    final salidaId = 'b' * 32;

    QrToken seed(String id, PunchType type) {
      final t = tokenOf(type, id: id);
      repo.tokens[id] = t;
      return t;
    }

    late FakeDeviceKeyStore keys;

    setUp(() {
      repo = FakeTerminalScanRepository()..enrolledKey = 'clave-del-dispositivo';
      keys = FakeDeviceKeyStore({'t1': 'clave-del-dispositivo'});
      service = TerminalScanService(repo, keys);
    });

    test('entrada: registra con la hora del servidor y confirma', () async {
      seed(entradaId, PunchType.entrada);
      final r = await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      expect(r.success, isTrue);
      expect(r.type, PunchType.entrada);
      expect(r.name, 'Mario');
      expect(r.at, repo.serverTime);
      expect(repo.commits, ['entrada:w1']);
    });

    test('salida después de la entrada', () async {
      seed(entradaId, PunchType.entrada);
      seed(salidaId, PunchType.salida);
      await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      final r = await service.process(QrPayload.encode(salidaId), terminalUid: 't1');
      expect(r.success, isTrue);
      expect(r.type, PunchType.salida);
      expect(repo.states['w1']!.abierta, isFalse);
    });

    test('un QR no se reutiliza', () async {
      seed(entradaId, PunchType.entrada);
      await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      final again = await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      expect(again.success, isFalse);
      expect(again.message, contains('utilizado'));
      expect(repo.commits, hasLength(1));
    });

    test('impide entradas duplicadas con otro QR', () async {
      seed(entradaId, PunchType.entrada);
      seed('c' * 32, PunchType.entrada);
      await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      final r = await service.process(QrPayload.encode('c' * 32), terminalUid: 't1');
      expect(r.success, isFalse);
      expect(repo.commits, hasLength(1));
    });

    test('impide salida sin entrada', () async {
      seed(salidaId, PunchType.salida);
      final r = await service.process(QrPayload.encode(salidaId), terminalUid: 't1');
      expect(r.success, isFalse);
      expect(repo.commits, isEmpty);
    });

    test('QR ajeno o inexistente no registra nada', () async {
      expect((await service.process('hola', terminalUid: 't1')).success, isFalse);
      expect((await service.process(QrPayload.encode('d' * 32), terminalUid: 't1')).success, isFalse);
      expect(repo.commits, isEmpty);
    });

    test('credenciales copiadas a otro equipo (sin el secreto del dispositivo) no marcan', () async {
      seed(entradaId, PunchType.entrada);
      // Equipo sin secreto local.
      final copied = TerminalScanService(repo, FakeDeviceKeyStore());
      final r = await copied.process(QrPayload.encode(entradaId), terminalUid: 't1');
      expect(r.success, isFalse);
      expect(repo.commits, isEmpty);
      // Equipo con un secreto distinto: el servidor lo rechaza.
      final forged = TerminalScanService(repo, FakeDeviceKeyStore({'t1': 'otra-clave'}));
      final r2 = await forged.process(QrPayload.encode(entradaId), terminalUid: 't1');
      expect(r2.success, isFalse);
      expect(repo.commits, isEmpty);
    });

    test('si el servidor rechaza (vencido / inactivo / terminal no autorizada) no se confirma', () async {
      seed(entradaId, PunchType.entrada);
      repo.serverRejects = true;
      final r = await service.process(QrPayload.encode(entradaId), terminalUid: 't1');
      expect(r.success, isFalse);
      expect(r.message, contains('servidor'));
      expect(repo.commits, isEmpty);
    });
  });

  group('enlace terminal ↔ dispositivo', () {
    test('el primer inicio registra un secreto local y en el servidor', () async {
      final repo = FakeTerminalScanRepository();
      final store = FakeDeviceKeyStore();
      final status = await TerminalBindingService(store, repo).ensureBound('t1');
      expect(status, isA<DeviceBound>());
      expect(store.keys['t1'], isNotNull);
      expect(store.keys['t1'], repo.enrolledKey);
      expect(store.keys['t1']!.length, greaterThanOrEqualTo(32));
    });

    test('los siguientes inicios reutilizan el secreto sin volver a registrarlo', () async {
      final repo = FakeTerminalScanRepository();
      final store = FakeDeviceKeyStore();
      final service = TerminalBindingService(store, repo);
      await service.ensureBound('t1');
      final first = store.keys['t1'];
      await service.ensureBound('t1');
      expect(store.keys['t1'], first);
    });

    test('un segundo equipo con las mismas credenciales no puede enlazarse', () async {
      final repo = FakeTerminalScanRepository();
      await TerminalBindingService(FakeDeviceKeyStore(), repo).ensureBound('t1');
      final intruder = FakeDeviceKeyStore();
      final status = await TerminalBindingService(intruder, repo).ensureBound('t1');
      expect(status, isA<DeviceNotBound>());
      expect(intruder.keys, isEmpty);
    });

    test('cada secreto generado es distinto', () {
      expect(TerminalBindingService.generateKey(), isNot(TerminalBindingService.generateKey()));
    });

    test('solo el Superadmin restablece el enlace', () async {
      final terminals = FakeTerminalRepository();
      final service = TerminalAdminService(terminals, FakeAccountCreator());
      const t = AttendanceTerminal(uid: 't1', nombre: 'Tablet', activo: true);
      await expectLater(service.resetDeviceLink(actorOf(UserRole.admin), t), throwsA(isA<AppFailure>()));
      await service.resetDeviceLink(actorOf(UserRole.superadmin), t);
      expect(terminals.resets, ['t1']);
    });

    test('si falla autorizar la terminal, la cuenta recién creada se elimina', () async {
      final accounts = FakeAccountCreator();
      final service = TerminalAdminService(_FailingTerminals(), accounts);
      await expectLater(
        service.register(actorOf(UserRole.superadmin), nombre: 'Tablet', email: 't@granja.pe', password: 'clavesegura1'),
        throwsA(anything),
      );
      expect(accounts.accounts.single.rolledBack, isTrue);
      expect(accounts.accounts.single.committed, isFalse);
    });
  });

  group('terminales: sesión y navegación', () {
    const nav = RoleNavigation(PermissionService());
    const redirect = AuthRedirect(nav);
    const terminal = AttendanceTerminal(uid: 't1', nombre: 'Tablet', activo: true);

    test('una cuenta sin perfil pero con terminal activa es TerminalAuthenticated', () {
      expect(SessionResolver.fromAccount(null, terminal), isA<TerminalAuthenticated>());
    });

    test('terminal revocada o cuenta sin ningún registro: acceso denegado', () {
      expect(
        SessionResolver.fromAccount(null, const AttendanceTerminal(uid: 't', nombre: 'x', activo: false)),
        isA<AccessDenied>(),
      );
      expect(SessionResolver.fromAccount(null, null), isA<AccessDenied>());
    });

    test('un perfil de personal tiene prioridad sobre terminal', () {
      expect(SessionResolver.fromAccount(buildUser(), terminal), isA<Authenticated>());
    });

    test('la terminal solo puede estar en /asistencia/terminal', () {
      const session = TerminalAuthenticated(terminal);
      expect(redirect.redirect(AppRoute.attendanceTerminal.path, session), isNull);
      expect(redirect.redirect(AppRoute.dashboard.path, session), AppRoute.attendanceTerminal.path);
      expect(redirect.redirect(AppRoute.login.path, session), AppRoute.attendanceTerminal.path);
    });

    test('el personal NO puede usar la pantalla de terminal desde su dispositivo', () {
      for (final role in UserRole.values) {
        final session = Authenticated(buildUser(role: role));
        final target = redirect.redirect(AppRoute.attendanceTerminal.path, session);
        expect(target, isNot(AppRoute.attendanceTerminal.path), reason: role.name);
        expect(target, isNotNull, reason: role.name);
      }
    });

    test('un anónimo no llega a la terminal', () {
      expect(redirect.redirect(AppRoute.attendanceTerminal.path, const Unauthenticated()),
          isNot(AppRoute.attendanceTerminal.path));
    });

    test('solo el Superadmin autoriza y revoca terminales', () async {
      final terminals = FakeTerminalRepository();
      final accounts = FakeAccountCreator();
      final service = TerminalAdminService(terminals, accounts);
      await expectLater(
        service.register(actorOf(UserRole.admin), nombre: 'Tablet', email: 't@granja.pe', password: 'clavesegura1'),
        throwsA(isA<AppFailure>()),
      );
      expect(accounts.created, isEmpty);

      final boss = actorOf(UserRole.superadmin);
      await service.register(boss, nombre: 'Tablet salón', email: 'T@granja.pe', password: 'clavesegura1');
      expect(accounts.created.single, ('t@granja.pe', 'clavesegura1'));
      expect(terminals.terminals['term-1']!.activo, isTrue);

      await service.setActive(boss, terminals.terminals['term-1']!, active: false);
      expect(terminals.terminals['term-1']!.activo, isFalse);
      await expectLater(
        service.setActive(actorOf(UserRole.admin), terminals.terminals['term-1']!, active: true),
        throwsA(isA<AppFailure>()),
      );
    });

    test('la contraseña de la terminal debe ser robusta', () {
      final service = TerminalAdminService(FakeTerminalRepository(), FakeAccountCreator());
      expect(
        service.register(actorOf(UserRole.superadmin), nombre: 'T1', email: 't@granja.pe', password: 'corta'),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('permisos de asistencia', () {
    const service = PermissionService();

    test('todos los roles generan su propio QR', () {
      for (final r in UserRole.values) {
        expect(service.can(r, Permission.ownAttendance), isTrue, reason: r.name);
      }
    });

    test('solo admin y superadmin administran la asistencia', () {
      for (final r in UserRole.values) {
        final expected = r == UserRole.admin || r == UserRole.superadmin;
        expect(service.can(r, Permission.manageAttendance), expected, reason: r.name);
      }
    });

    test('terminales, restricciones y auditoría: solo Superadmin', () {
      for (final r in UserRole.values) {
        final isSuper = r == UserRole.superadmin;
        expect(service.can(r, Permission.manageTerminals), isSuper);
        expect(service.can(r, Permission.manageRestrictions), isSuper);
        expect(service.can(r, Permission.viewAudit), isSuper);
      }
    });

    test('el mesero ve su asistencia pero no las pantallas administrativas', () {
      final routes = nav().routesFor(UserRole.mesero);
      expect(routes, contains(AppRoute.myAttendance));
      expect(routes, isNot(contains(AppRoute.attendanceAdmin)));
      expect(routes, isNot(contains(AppRoute.terminals)));
      expect(routes, isNot(contains(AppRoute.restrictions)));
      expect(routes, isNot(contains(AppRoute.users)));
    });

    test('la ruta de inicio de cada rol no cambia con la Fase 3', () {
      final n = nav();
      expect(n.homeFor(UserRole.superadmin), AppRoute.dashboard);
      expect(n.homeFor(UserRole.admin), AppRoute.dashboard);
      expect(n.homeFor(UserRole.mesero), AppRoute.waiter);
      expect(n.homeFor(UserRole.cocina), AppRoute.kitchen);
      expect(n.homeFor(UserRole.cajero), AppRoute.cashier);
      expect(n.homeFor(UserRole.almacen), AppRoute.inventory);
    });
  });

  group('horarios', () {
    const day = Schedule(
      id: 'dia', nombre: 'Día', inicioMin: 8 * 60, finMin: 16 * 60, toleranciaMin: 10, dias: [1, 2, 3, 4, 5],
    );
    const night = Schedule(
      id: 'noche', nombre: 'Noche', inicioMin: 22 * 60, finMin: 6 * 60, toleranciaMin: 10, dias: [1, 2, 3, 4, 5, 6, 7],
    );

    test('turno nocturno cruza la medianoche', () {
      expect(night.esNocturno, isTrue);
      expect(day.esNocturno, isFalse);
      expect(night.duracion, const Duration(hours: 8));
      final d = LimaTime.instant(2026, 10, 26);
      expect(night.endOn(d), LimaTime.instant(2026, 10, 27, 6));
    });

    test('tolerancia: dentro no es tardanza, fuera sí', () {
      expect(day.lateMinutes(LimaTime.instant(2026, 10, 26, 8, 10)), 0);
      expect(day.lateMinutes(LimaTime.instant(2026, 10, 26, 8, 25)), 15);
      expect(day.lateMinutes(LimaTime.instant(2026, 10, 26, 7, 30)), 0);
    });

    test('turno nocturno: la entrada tras medianoche se compara con el inicio del día anterior', () {
      expect(night.lateMinutes(LimaTime.instant(2026, 10, 26, 21, 50)), 0);
      expect(night.lateMinutes(LimaTime.instant(2026, 10, 26, 22, 30)), 20);
      expect(night.lateMinutes(LimaTime.instant(2026, 10, 27, 0, 40)), 150);
    });

    test('validación del formulario', () {
      String? v({String n = 'Mañana', String? i = '08:00', String? f = '16:00', int t = 10, List<int> d = const [1]}) =>
          Schedule.validate(nombre: n, horaInicio: i, horaFin: f, toleranciaMin: t, dias: d);
      expect(v(), isNull);
      expect(v(i: '8:00'), isNotNull);
      expect(v(i: '25:00'), isNotNull);
      expect(v(i: '08:00', f: '08:00'), isNotNull);
      expect(v(t: 500), isNotNull);
      expect(v(d: []), isNotNull);
      expect(v(n: ''), isNotNull);
      expect(v(i: '22:00', f: '06:00'), isNull); // nocturno válido
    });

    test('aplica solo los días configurados (hora de Lima)', () {
      final monday = LimaTime.instant(2026, 10, 26);
      final sunday = LimaTime.instant(2026, 10, 25);
      expect(day.appliesOn(monday), isTrue);
      expect(day.appliesOn(sunday), isFalse);
    });
  });

  group('dashboard de asistencia', () {
    final day = Schedule(
      id: 'dia', nombre: 'Día', inicioMin: 8 * 60, finMin: 16 * 60, toleranciaMin: 10, dias: const [1, 2, 3, 4, 5],
    );
    final people = [
      memberOf('puntual', horarioId: 'dia', apellidos: 'Aguirre'),
      memberOf('tarde', horarioId: 'dia', apellidos: 'Benites'),
      memberOf('falta', horarioId: 'dia', apellidos: 'Castro'),
      memberOf('sinHorario', apellidos: 'Díaz'),
      memberOf('baja', horarioId: 'dia', apellidos: 'Egusquiza', estado: StaffStatus.baja),
    ];
    AttendanceRecord rec(String uid, DateTime entrada, {DateTime? salida}) =>
        AttendanceRecord(id: 'r-$uid', uid: uid, entrada: entrada, salida: salida);

    test('clasifica presentes, tardanzas y ausencias; sin horario ni bajas quedan fuera', () {
      final now = LimaTime.instant(2026, 10, 26, 10); // lunes 10:00
      final report = AttendanceReport.build(
        now: now,
        staff: people,
        schedules: {'dia': day},
        records: [
          rec('puntual', LimaTime.instant(2026, 10, 26, 7, 55)),
          rec('tarde', LimaTime.instant(2026, 10, 26, 8, 40)),
        ],
      );
      expect(report.onTime.map((d) => d.staff.uid), ['puntual']);
      expect(report.late.single.staff.uid, 'tarde');
      expect(report.late.single.lateMinutes, 30);
      expect(report.absent.single.staff.uid, 'falta');
      expect(report.present, hasLength(2)); // ambos con jornada abierta
      expect(report.days.map((d) => d.staff.uid), isNot(contains('sinHorario')));
      expect(report.days.map((d) => d.staff.uid), isNot(contains('baja')));
    });

    test('antes de terminar la tolerancia nadie es ausente', () {
      final report = AttendanceReport.build(
        now: LimaTime.instant(2026, 10, 26, 8, 5),
        staff: people,
        schedules: {'dia': day},
        records: const [],
      );
      expect(report.absent, isEmpty);
      expect(report.days.every((d) => d.status == DayStatus.pendiente), isTrue);
    });

    test('un día sin turno (domingo) no genera ausencias', () {
      final report = AttendanceReport.build(
        now: LimaTime.instant(2026, 10, 25, 12),
        staff: people,
        schedules: {'dia': day},
        records: const [],
      );
      expect(report.days, isEmpty);
    });

    test('un turno nocturno iniciado ayer sigue presente hoy', () {
      final report = AttendanceReport.build(
        now: LimaTime.instant(2026, 10, 27, 1),
        staff: const [],
        schedules: const {},
        records: [rec('w', LimaTime.instant(2026, 10, 26, 22, 0))],
      );
      expect(report.present.single.uid, 'w');
    });
  });

  group('regularización', () {
    const reg = Regularization();
    final now = DateTime.utc(2026, 10, 26, 15);
    final entrada = DateTime.utc(2026, 10, 26, 13);
    final salida = DateTime.utc(2026, 10, 26, 14);

    void run(
      AppUser actor, {
      UserRole target = UserRole.mesero,
      String uid = 'w1',
      DateTime? e,
      DateTime? s,
      String motivo = 'Olvidó marcar la entrada',
    }) =>
        reg.validate(
          actor: actor,
          targetRole: target,
          targetUid: uid,
          entrada: e ?? entrada,
          salida: s,
          motivo: motivo,
          now: now,
        );

    test('Superadmin y Admin autorizado pueden; Admin sin autorización no', () {
      expect(reg.canRegularize(actorOf(UserRole.superadmin)), isTrue);
      expect(reg.canRegularize(actorOf(UserRole.admin, regularize: true)), isTrue);
      expect(reg.canRegularize(actorOf(UserRole.admin)), isFalse);
      expect(reg.canRegularize(actorOf(UserRole.mesero, regularize: true)), isFalse);
    });

    test('motivo obligatorio', () {
      expect(() => run(actorOf(UserRole.superadmin), motivo: 'corto'), throwsA(isA<AppFailure>()));
      expect(() => run(actorOf(UserRole.superadmin), motivo: ''), throwsA(isA<AppFailure>()));
      expect(() => run(actorOf(UserRole.superadmin)), returnsNormally);
    });

    test('no sobre sí mismo ni sobre jerarquías superiores', () {
      final admin = actorOf(UserRole.admin, uid: 'a1', regularize: true);
      expect(() => run(admin, uid: 'a1', target: UserRole.mesero), throwsA(isA<AppFailure>()));
      expect(() => run(admin, target: UserRole.admin), throwsA(isA<AppFailure>()));
      expect(() => run(admin, target: UserRole.superadmin), throwsA(isA<AppFailure>()));
    });

    test('fechas coherentes', () {
      final boss = actorOf(UserRole.superadmin);
      expect(() => run(boss, e: now.add(const Duration(hours: 1))), throwsA(isA<AppFailure>()));
      expect(() => run(boss, s: entrada), throwsA(isA<AppFailure>()));
      expect(() => run(boss, s: now.add(const Duration(hours: 1))), throwsA(isA<AppFailure>()));
      expect(() => run(boss, s: salida), returnsNormally);
    });

    test('marcación supervisada para quien no tiene celular', () {
      expect(reg.originFor(supervised: true), AttendanceOrigin.supervisada);
      expect(reg.originFor(supervised: false), AttendanceOrigin.regularizada);
    });
  });
}

class _FailingTerminals extends FakeTerminalRepository {
  @override
  Future<void> authorize(AppUser actor, {required String nombre, required String uid}) =>
      Future.error(const AppFailure('permission-denied', code: 'permission-denied'));
}
