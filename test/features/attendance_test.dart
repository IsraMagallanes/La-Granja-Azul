import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/core/routing/app_routes.dart';
import 'package:granja_azul/core/routing/auth_redirect.dart';
import 'package:granja_azul/core/time/lima_time.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/attendance/models/schedule.dart';
import 'package:granja_azul/features/attendance/services/attendance_report.dart';
import 'package:granja_azul/features/attendance/services/attendance_services.dart';
import 'package:granja_azul/features/attendance/services/qr_payload.dart';
import 'package:granja_azul/features/attendance/services/regularization.dart';
import 'package:granja_azul/features/attendance/services/scan_validator.dart';
import 'package:granja_azul/features/auth/models/session_state.dart';
import 'package:granja_azul/features/auth/services/session_resolver.dart';
import 'package:granja_azul/features/roles/models/permission.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/roles/services/permission_service.dart';
import 'package:granja_azul/features/roles/services/role_navigation.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/users/models/app_user.dart';

import '../support/phase3_fakes.dart';

RoleNavigation nav() => const RoleNavigation(PermissionService());

QrToken tokenOf(
  UserRole generator, {
  String id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
  String uid = 'g1',
  DateTime? creadoEn,
}) => QrToken(
  id: id,
  generadorUid: uid,
  generadorRol: generator,
  nombreMostrar: 'Gema',
  creadoEn: creadoEn ?? DateTime.utc(2026, 10, 26, 13),
);

final scanNow = DateTime.utc(2026, 10, 26, 13, 0, 10);

void main() {
  group('hora de Lima', () {
    test('Lima es UTC-5 todo el año', () {
      final utc = DateTime.utc(2026, 10, 26, 3, 30); // 22:30 del 25 en Lima
      expect(LimaTime.dateKey(utc), '2026-10-25');
      expect(LimaTime.formatTime(utc), '22:30');
      expect(LimaTime.instant(2026, 10, 25, 22, 30), utc);
    });

    test('inicio del día de Lima', () {
      expect(
        LimaTime.startOfDay(DateTime.utc(2026, 10, 26, 3)),
        DateTime.utc(2026, 10, 25, 5),
      );
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

  group('quién genera y quién escanea el QR', () {
    const policy = QrPolicy();

    test('generan exclusivamente Superadmin, Admin y Cajero', () {
      for (final r in UserRole.values) {
        final expected =
            r == UserRole.superadmin ||
            r == UserRole.admin ||
            r == UserRole.cajero;
        expect(policy.canGenerate(r), expected, reason: r.name);
      }
    });

    test('escanean exclusivamente Mesero, Cocina y Cajero', () {
      for (final r in UserRole.values) {
        final expected =
            r == UserRole.mesero ||
            r == UserRole.cocina ||
            r == UserRole.cajero;
        expect(policy.canScan(r), expected, reason: r.name);
      }
    });

    test('Mesero y Cocina escanean QR de cualquier generador autorizado', () {
      for (final scanner in [UserRole.mesero, UserRole.cocina]) {
        for (final generator in [
          UserRole.superadmin,
          UserRole.admin,
          UserRole.cajero,
        ]) {
          expect(policy.canScanFrom(scanner, generator), isTrue);
        }
        expect(policy.canScanFrom(scanner, UserRole.mesero), isFalse);
        expect(policy.canScanFrom(scanner, UserRole.cocina), isFalse);
      }
    });

    test('el Cajero solo escanea QR de Admin o Superadmin', () {
      expect(policy.canScanFrom(UserRole.cajero, UserRole.admin), isTrue);
      expect(policy.canScanFrom(UserRole.cajero, UserRole.superadmin), isTrue);
      expect(policy.canScanFrom(UserRole.cajero, UserRole.cajero), isFalse);
      expect(policy.canScanFrom(UserRole.cajero, UserRole.mesero), isFalse);
    });

    test('Admin y Superadmin no escanean', () {
      expect(policy.canScanFrom(UserRole.admin, UserRole.cajero), isFalse);
      expect(
        policy.canScanFrom(UserRole.superadmin, UserRole.admin),
        isFalse,
      );
    });
  });

  group('generación del QR', () {
    late FakeQrGenerationRepository repo;
    late QrGenerationService service;

    setUp(() {
      repo = FakeQrGenerationRepository();
      service = QrGenerationService(repo);
    });

    test('Superadmin, Admin y Cajero generan un QR con vencimiento', () async {
      final now = DateTime(2026, 10, 26, 8);
      for (final role in [
        UserRole.superadmin,
        UserRole.admin,
        UserRole.cajero,
      ]) {
        final qr = await service.issue(
          actorOf(role, uid: 'g-${role.name}'),
          clock: () => now,
        );
        expect(qr.expiresAt, now.add(const Duration(seconds: 45)));
        expect(QrPayload.decode(qr.payload), qr.token.id);
        expect(qr.token.generadorRol, role);
      }
      expect(repo.created, hasLength(3));
    });

    test('Mesero y Cocina NO generan QR: se rechaza sin tocar el servidor', () {
      for (final role in [UserRole.mesero, UserRole.cocina]) {
        expect(
          service.issue(actorOf(role)),
          throwsA(isA<AppFailure>()),
          reason: role.name,
        );
      }
      expect(repo.created, isEmpty);
    });

    test('un generador inactivo no genera QR', () {
      final inactive = AppUser(
        uid: 'g1',
        email: 'g1@granja.pe',
        nombre: 'G',
        role: UserRole.cajero,
        activo: false,
      );
      expect(service.issue(inactive), throwsA(isA<AppFailure>()));
      expect(repo.created, isEmpty);
    });

    test('la solicitud de corrección exige motivo', () async {
      final repo = FakeWorkerAttendanceRepository();
      final self = AttendanceSelfService(repo);
      final worker = actorOf(UserRole.mesero, uid: 'w1');
      await expectLater(
        self.requestCorrection(
          worker: worker,
          fecha: '2026-10-25',
          tipo: 'entrada',
          motivo: 'x',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.corrections, isEmpty);
      await self.requestCorrection(
        worker: worker,
        fecha: '2026-10-25',
        tipo: 'entrada',
        motivo: 'Olvidé marcar la entrada del turno de la tarde',
      );
      expect(repo.corrections, hasLength(1));
    });
  });

  group('ScanValidator', () {
    const validator = ScanValidator();

    ScanDecision eval(
      QrToken? token,
      UserRole scanner, {
      AttendanceState? state,
      String uid = 'w1',
      DateTime? now,
    }) => validator.evaluate(
      token: token,
      scannerRole: scanner,
      scannerUid: uid,
      now: now ?? scanNow,
      state: state,
    );

    test('QR inexistente o vencido', () {
      expect(eval(null, UserRole.mesero), isA<ScanRejected>());
      final old = tokenOf(UserRole.admin);
      expect(
        eval(old, UserRole.mesero, now: old.creadoEn!.add(QrToken.lifetime)),
        isA<ScanRejected>(),
      );
    });

    test('nadie escanea su propio QR', () {
      expect(
        eval(tokenOf(UserRole.cajero, uid: 'w1'), UserRole.cajero, uid: 'w1'),
        isA<ScanRejected>(),
      );
    });

    test('un rol que no escanea no registra nada', () {
      for (final role in [UserRole.admin, UserRole.superadmin]) {
        expect(eval(tokenOf(UserRole.admin), role), isA<ScanRejected>());
      }
    });

    test('el Cajero rechaza un QR de otro Cajero y acepta uno de Admin', () {
      expect(
        eval(tokenOf(UserRole.cajero), UserRole.cajero),
        isA<ScanRejected>(),
      );
      expect(
        eval(tokenOf(UserRole.admin), UserRole.cajero),
        isA<ScanProceed>(),
      );
      expect(
        eval(tokenOf(UserRole.superadmin), UserRole.cajero),
        isA<ScanProceed>(),
      );
    });

    test('Mesero y Cocina aceptan QR de Cajero, Admin y Superadmin', () {
      for (final scanner in [UserRole.mesero, UserRole.cocina]) {
        for (final gen in [
          UserRole.cajero,
          UserRole.admin,
          UserRole.superadmin,
        ]) {
          expect(eval(tokenOf(gen), scanner), isA<ScanProceed>());
        }
      }
    });

    test('entrada o salida se determinan solos según la jornada', () {
      final token = tokenOf(UserRole.admin);
      final closed = eval(token, UserRole.mesero) as ScanProceed;
      expect(closed.type, PunchType.entrada);
      final afterExit = eval(
        token,
        UserRole.mesero,
        state: const AttendanceState(abierta: false, asistenciaId: 'a1'),
      ) as ScanProceed;
      expect(afterExit.type, PunchType.entrada);
      final open = eval(
        token,
        UserRole.mesero,
        state: const AttendanceState(abierta: true, asistenciaId: 'a1'),
      ) as ScanProceed;
      expect(open.type, PunchType.salida);
    });

    test('el mismo QR no encadena dos marcaciones', () {
      final token = tokenOf(UserRole.admin);
      expect(
        eval(
          token,
          UserRole.mesero,
          state: AttendanceState(
            abierta: true,
            asistenciaId: 'a1',
            tokenId: token.id,
          ),
        ),
        isA<ScanRejected>(),
      );
    });
  });

  group('escaneo', () {
    late FakeQrScanRepository repo;
    late AttendanceScanService service;
    final entradaId = 'a' * 32;
    final salidaId = 'b' * 32;
    final mesero = actorOf(UserRole.mesero, uid: 'w1');
    final cajero = actorOf(UserRole.cajero, uid: 'c1');

    QrToken seed(String id, UserRole generator, {String uid = 'g1'}) {
      final t = tokenOf(generator, id: id, uid: uid);
      repo.tokens[id] = t;
      return t;
    }

    setUp(() {
      repo = FakeQrScanRepository()
        ..roles.addAll({'w1': UserRole.mesero, 'c1': UserRole.cajero});
      service = AttendanceScanService(repo);
    });

    Future<ScanResult> scan(String id, AppUser who) =>
        service.process(QrPayload.encode(id), scanner: who, clock: () => scanNow);

    test('entrada y luego salida, sin elegir cuál: la decide la jornada', () async {
      seed(entradaId, UserRole.admin);
      seed(salidaId, UserRole.cajero, uid: 'g2');
      final entrada = await scan(entradaId, mesero);
      expect(entrada.success, isTrue);
      expect(entrada.type, PunchType.entrada);
      expect(entrada.at, repo.serverTime);
      final salida = await scan(salidaId, mesero);
      expect(salida.success, isTrue);
      expect(salida.type, PunchType.salida);
      expect(repo.commits, ['entrada:w1', 'salida:w1']);
    });

    test('Cajero: acepta QR de Admin y rechaza QR de otro Cajero', () async {
      seed(entradaId, UserRole.cajero, uid: 'c2');
      final rejected = await scan(entradaId, cajero);
      expect(rejected.success, isFalse);
      expect(repo.commits, isEmpty);
      seed(salidaId, UserRole.admin);
      expect((await scan(salidaId, cajero)).success, isTrue);
    });

    test('Admin y Superadmin no registran asistencia por QR', () async {
      seed(entradaId, UserRole.cajero);
      for (final role in [UserRole.admin, UserRole.superadmin]) {
        final r = await scan(entradaId, actorOf(role, uid: 'x-${role.name}'));
        expect(r.success, isFalse, reason: role.name);
      }
      expect(repo.commits, isEmpty);
    });

    test('un QR vencido o ajeno no registra nada', () async {
      expect((await scan(entradaId, mesero)).success, isFalse);
      repo.tokens[entradaId] = tokenOf(
        UserRole.admin,
        id: entradaId,
        creadoEn: scanNow.subtract(const Duration(minutes: 5)),
      );
      expect((await scan(entradaId, mesero)).success, isFalse);
      final r = await service.process('https://ejemplo.com', scanner: mesero);
      expect(r.success, isFalse);
      expect(repo.commits, isEmpty);
    });

    test('el mismo QR no se encadena (entrada y salida inmediata)', () async {
      seed(entradaId, UserRole.admin);
      expect((await scan(entradaId, mesero)).success, isTrue);
      expect((await scan(entradaId, mesero)).success, isFalse);
      expect(repo.commits, ['entrada:w1']);
    });

    test('un trabajador inactivo no marca', () async {
      seed(entradaId, UserRole.admin);
      final inactive = AppUser(
        uid: 'w1',
        email: 'w1@granja.pe',
        nombre: 'W',
        role: UserRole.mesero,
        activo: false,
      );
      expect((await scan(entradaId, inactive)).success, isFalse);
      expect(repo.commits, isEmpty);
    });

    test('si el servidor rechaza no se confirma', () async {
      seed(entradaId, UserRole.admin);
      repo.serverRejects = true;
      final r = await scan(entradaId, mesero);
      expect(r.success, isFalse);
      expect(r.message, isNotEmpty);
      expect(repo.commits, isEmpty);
    });
  });

  group('sistema antiguo de terminales retirado', () {
    const redirect = AuthRedirect(RoleNavigation(PermissionService()));
    const oldRoutes = ['/asistencia/terminal', '/app/terminales'];

    test('las rutas antiguas ya no existen', () {
      for (final path in oldRoutes) {
        expect(AppRoute.fromPath(path), isNull, reason: path);
      }
    });

    test('quien entra a una ruta antigua vuelve a su inicio, sea cual sea su rol', () {
      for (final role in UserRole.values) {
        final s = Authenticated(actorOf(role));
        for (final path in oldRoutes) {
          expect(
            redirect.redirect(path, s),
            nav().homeFor(role).path,
            reason: '${role.name} $path',
          );
        }
      }
    });

    test('sin sesión, las rutas antiguas llevan al acceso, no a una terminal', () {
      for (final path in oldRoutes) {
        expect(redirect.redirect(path, const Unauthenticated()), isNot(path));
      }
    });

    test('una cuenta sin perfil de personal queda sin acceso (ya no hay cuentas de terminal)', () {
      expect(SessionResolver.fromProfile(null), isA<AccessDenied>());
    });

    test('ningún rol ve una opción «Terminales» en el menú', () {
      for (final role in UserRole.values) {
        expect(
          nav().routesFor(role).where((r) => r.label == 'Terminales'),
          isEmpty,
          reason: role.name,
        );
      }
    });
  });

  group('permisos de asistencia', () {
    const service = PermissionService();

    test('todos los roles ven su propia asistencia', () {
      for (final r in UserRole.values) {
        expect(
          service.can(r, Permission.ownAttendance),
          isTrue,
          reason: r.name,
        );
      }
    });

    test('generar QR: solo Superadmin, Admin y Cajero', () {
      for (final r in UserRole.values) {
        final expected = {
          UserRole.superadmin,
          UserRole.admin,
          UserRole.cajero,
        }.contains(r);
        expect(
          service.can(r, Permission.generateAttendanceQr),
          expected,
          reason: r.name,
        );
        expect(
          nav().routesFor(r).contains(AppRoute.generateQr),
          expected,
          reason: r.name,
        );
      }
    });

    test('escanear QR: solo Mesero, Cocina y Cajero', () {
      for (final r in UserRole.values) {
        final expected = {
          UserRole.mesero,
          UserRole.cocina,
          UserRole.cajero,
        }.contains(r);
        expect(
          service.can(r, Permission.scanAttendanceQr),
          expected,
          reason: r.name,
        );
        expect(
          nav().routesFor(r).contains(AppRoute.scanQr),
          expected,
          reason: r.name,
        );
      }
    });

    test('Mesero y Cocina no ven ninguna pantalla de generar QR', () {
      for (final r in [UserRole.mesero, UserRole.cocina]) {
        expect(nav().routesFor(r), isNot(contains(AppRoute.generateQr)));
        expect(nav().routesFor(r), contains(AppRoute.scanQr));
      }
    });

    test('solo admin y superadmin administran la asistencia', () {
      for (final r in UserRole.values) {
        final expected = r == UserRole.admin || r == UserRole.superadmin;
        expect(
          service.can(r, Permission.manageAttendance),
          expected,
          reason: r.name,
        );
      }
    });

    test('restricciones y auditoría: solo Superadmin', () {
      for (final r in UserRole.values) {
        final isSuper = r == UserRole.superadmin;
        expect(service.can(r, Permission.manageRestrictions), isSuper);
        expect(service.can(r, Permission.viewAudit), isSuper);
      }
    });

    test(
      'el mesero ve su asistencia pero no las pantallas administrativas',
      () {
        final routes = nav().routesFor(UserRole.mesero);
        expect(routes, contains(AppRoute.myAttendance));
        expect(routes, isNot(contains(AppRoute.attendanceAdmin)));
        expect(routes, isNot(contains(AppRoute.restrictions)));
        expect(routes, isNot(contains(AppRoute.users)));
      },
    );

    test('la ruta de inicio de cada rol no cambia con la Fase 3', () {
      final n = nav();
      expect(n.homeFor(UserRole.superadmin), AppRoute.dashboard);
      expect(n.homeFor(UserRole.admin), AppRoute.dashboard);
      expect(n.homeFor(UserRole.mesero), AppRoute.waiter);
      expect(n.homeFor(UserRole.cocina), AppRoute.kitchen);
      expect(n.homeFor(UserRole.cajero), AppRoute.cashier);
    });
  });

  group('horarios', () {
    const day = Schedule(
      id: 'dia',
      nombre: 'Día',
      inicioMin: 8 * 60,
      finMin: 16 * 60,
      toleranciaMin: 10,
      dias: [1, 2, 3, 4, 5],
    );
    const night = Schedule(
      id: 'noche',
      nombre: 'Noche',
      inicioMin: 22 * 60,
      finMin: 6 * 60,
      toleranciaMin: 10,
      dias: [1, 2, 3, 4, 5, 6, 7],
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
      String? v({
        String n = 'Mañana',
        String? i = '08:00',
        String? f = '16:00',
        int t = 10,
        List<int> d = const [1],
      }) => Schedule.validate(
        nombre: n,
        horaInicio: i,
        horaFin: f,
        toleranciaMin: t,
        dias: d,
      );
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
      id: 'dia',
      nombre: 'Día',
      inicioMin: 8 * 60,
      finMin: 16 * 60,
      toleranciaMin: 10,
      dias: const [1, 2, 3, 4, 5],
    );
    final people = [
      memberOf('puntual', horarioId: 'dia', apellidos: 'Aguirre'),
      memberOf('tarde', horarioId: 'dia', apellidos: 'Benites'),
      memberOf('falta', horarioId: 'dia', apellidos: 'Castro'),
      memberOf('sinHorario', apellidos: 'Díaz'),
      memberOf(
        'baja',
        horarioId: 'dia',
        apellidos: 'Egusquiza',
        estado: StaffStatus.baja,
      ),
    ];
    AttendanceRecord rec(String uid, DateTime entrada, {DateTime? salida}) =>
        AttendanceRecord(
          id: 'r-$uid',
          uid: uid,
          entrada: entrada,
          salida: salida,
        );

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
      expect(
        report.days.map((d) => d.staff.uid),
        isNot(contains('sinHorario')),
      );
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
    }) => reg.validate(
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
      expect(
        reg.canRegularize(actorOf(UserRole.admin, regularize: true)),
        isTrue,
      );
      expect(reg.canRegularize(actorOf(UserRole.admin)), isFalse);
      expect(
        reg.canRegularize(actorOf(UserRole.mesero, regularize: true)),
        isFalse,
      );
    });

    test('motivo obligatorio', () {
      expect(
        () => run(actorOf(UserRole.superadmin), motivo: 'corto'),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => run(actorOf(UserRole.superadmin), motivo: ''),
        throwsA(isA<AppFailure>()),
      );
      expect(() => run(actorOf(UserRole.superadmin)), returnsNormally);
    });

    test('no sobre sí mismo ni sobre jerarquías superiores', () {
      final admin = actorOf(UserRole.admin, uid: 'a1', regularize: true);
      expect(
        () => run(admin, uid: 'a1', target: UserRole.mesero),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => run(admin, target: UserRole.admin),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => run(admin, target: UserRole.superadmin),
        throwsA(isA<AppFailure>()),
      );
    });

    test('fechas coherentes', () {
      final boss = actorOf(UserRole.superadmin);
      expect(
        () => run(boss, e: now.add(const Duration(hours: 1))),
        throwsA(isA<AppFailure>()),
      );
      expect(() => run(boss, s: entrada), throwsA(isA<AppFailure>()));
      expect(
        () => run(boss, s: now.add(const Duration(hours: 1))),
        throwsA(isA<AppFailure>()),
      );
      expect(() => run(boss, s: salida), returnsNormally);
    });

    test('marcación supervisada para quien no tiene celular', () {
      expect(reg.originFor(supervised: true), AttendanceOrigin.supervisada);
      expect(reg.originFor(supervised: false), AttendanceOrigin.regularizada);
    });
  });
}
