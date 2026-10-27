import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/core/validators/validators.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/models/document_type.dart';
import 'package:granja_azul/features/staff/models/rehire_restriction.dart';
import 'package:granja_azul/features/staff/models/staff_member.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/models/status_change.dart';
import 'package:granja_azul/features/staff/services/restriction_service.dart';
import 'package:granja_azul/features/staff/services/staff_list_query.dart';
import 'package:granja_azul/features/staff/services/staff_policy.dart';
import 'package:granja_azul/features/staff/services/staff_service.dart';
import 'package:granja_azul/features/staff/services/staff_validator.dart';

import '../support/phase3_fakes.dart';

void main() {
  group('validaciones de documentos y contacto', () {
    test('DNI: exactamente 8 dígitos', () {
      expect(Validators.dni('12345678'), isNull);
      expect(Validators.dni('1234567'), isNotNull);
      expect(Validators.dni('123456789'), isNotNull);
      expect(Validators.dni('1234567a'), isNotNull);
      expect(Validators.dni(''), isNotNull);
    });

    test('carné de extranjería: 9 a 12 alfanuméricos', () {
      expect(Validators.carnetExtranjeria('ABC123456'), isNull);
      expect(Validators.carnetExtranjeria('abc123456'), isNull);
      expect(Validators.carnetExtranjeria('123456789012'), isNull);
      expect(Validators.carnetExtranjeria('12345678'), isNotNull);
      expect(Validators.carnetExtranjeria('1234567890123'), isNotNull);
      expect(Validators.carnetExtranjeria('ABC-23456'), isNotNull);
    });

    test('celular: 9 dígitos que empiezan con 9; alterno opcional', () {
      expect(Validators.celular('987654321'), isNull);
      expect(Validators.celular('887654321'), isNotNull);
      expect(Validators.celular('98765432'), isNotNull);
      expect(Validators.celularOpcional(''), isNull);
      expect(Validators.celularOpcional(null), isNull);
      expect(Validators.celularOpcional('123'), isNotNull);
    });

    test('nombres con tildes y eñes válidos; números no', () {
      expect(Validators.persona('María José'), isNull);
      expect(Validators.persona("O'Brien"), isNull);
      expect(Validators.persona('Juan3'), isNotNull);
      expect(Validators.persona('A'), isNotNull);
    });

    test('el tipo de documento valida y normaliza', () {
      expect(DocumentType.dni.validate('12345678'), isNull);
      expect(DocumentType.ce.validate('abc123456'), isNull);
      expect(DocumentType.ce.normalize(' abc123456 '), 'ABC123456');
    });

    test('StaffValidator reporta cada campo inválido', () {
      const validator = StaffValidator();
      expect(validator.validate(draftOf()), isEmpty);
      final errors = validator.validate(draftOf(
        documento: '123',
        email: 'x',
        celular: '1',
        alterno: '2',
      ));
      expect(errors.keys, containsAll(['documento', 'email', 'celular', 'celularAlterno']));
    });

    test('el alterno no puede ser igual al celular principal', () {
      final errors = const StaffValidator()
          .validate(draftOf(celular: '912345678', alterno: '912345678'));
      expect(errors.containsKey('celularAlterno'), isTrue);
    });

    test('la fecha de ingreso no puede ser futura', () {
      final draft = draftOf();
      final errors = const StaffValidator()
          .validate(draft, today: DateTime(2026, 1, 1));
      expect(errors.containsKey('fechaIngreso'), isTrue);
    });
  });

  group('datos personales protegidos', () {
    test('el listado enmascara documento y celular', () {
      final m = memberOf('u1');
      expect(m.documentoEnmascarado, '12••••78');
      expect(m.celularEnmascarado, '••••••321');
      expect(m.documentoEnmascarado.contains('3456'), isFalse);
    });
  });

  group('jerarquía y escalamiento de privilegios', () {
    const policy = StaffPolicy();

    test('superadmin asigna admin y operativos, nunca superadmin', () {
      expect(policy.assignableRoles(UserRole.superadmin),
          {UserRole.admin, UserRole.mesero, UserRole.cocina, UserRole.cajero, UserRole.almacen});
      expect(policy.canAssign(UserRole.superadmin, UserRole.superadmin), isFalse);
    });

    test('admin solo asigna roles operativos', () {
      expect(policy.canAssign(UserRole.admin, UserRole.mesero), isTrue);
      expect(policy.canAssign(UserRole.admin, UserRole.admin), isFalse);
      expect(policy.canAssign(UserRole.admin, UserRole.superadmin), isFalse);
    });

    test('roles operativos no administran a nadie', () {
      for (final r in [UserRole.mesero, UserRole.cocina, UserRole.cajero, UserRole.almacen]) {
        expect(policy.assignableRoles(r), isEmpty);
      }
    });

    test('nadie se administra a sí mismo ni admin a otro admin', () {
      final self = memberOf('a1', role: UserRole.admin);
      expect(policy.canManage(actorRole: UserRole.admin, actorUid: 'a1', target: self), isFalse);
      expect(policy.canManage(actorRole: UserRole.superadmin, actorUid: 's1', target: self), isTrue);
      final other = memberOf('a2', role: UserRole.admin);
      expect(policy.canManage(actorRole: UserRole.admin, actorUid: 'a1', target: other), isFalse);
      final boss = memberOf('s1', role: UserRole.superadmin);
      expect(policy.canManage(actorRole: UserRole.superadmin, actorUid: 's2', target: boss), isFalse);
    });

    test('solo el superadmin gestiona restricciones y permisos de regularización', () {
      expect(policy.canManageRestrictions(UserRole.superadmin), isTrue);
      expect(policy.canManageRestrictions(UserRole.admin), isFalse);
      expect(policy.canGrantRegularization(UserRole.admin), isFalse);
    });
  });

  group('StaffService', () {
    late FakeStaffRepository staff;
    late FakeRestrictionRepository restrictions;
    late StaffService service;

    setUp(() {
      staff = FakeStaffRepository();
      restrictions = FakeRestrictionRepository();
      service = StaffService(staff, restrictions);
    });

    test('crea un trabajador válido', () async {
      final result = await service.create(actorOf(UserRole.admin), draftOf());
      expect(result.uid, 'uid-1');
      expect(result.restriction, isNull);
    });

    test('el alta informa si el correo de contraseña no pudo enviarse', () async {
      staff.resetEmailSent = false;
      final result = await service.create(actorOf(UserRole.admin), draftOf());
      expect(result.resetEmailSent, isFalse);
      expect(result.uid, isNotEmpty);
    });

    test('admin no puede crear un admin (escalamiento)', () {
      expect(
        service.create(actorOf(UserRole.admin), draftOf(role: UserRole.admin)),
        throwsA(isA<AppFailure>()),
      );
    });

    test('rechaza documento y correo duplicados, incluso de personal dado de baja', () async {
      staff.documents.add('87654321'); // p. ej. un trabajador ya dado de baja
      await expectLater(
        service.create(actorOf(UserRole.admin), draftOf()),
        throwsA(isA<AppFailure>().having((e) => e.message, 'message', contains('documento'))),
      );
      staff.documents.clear();
      staff.emails.add('nuevo@granja.pe');
      await expectLater(
        service.create(actorOf(UserRole.admin), draftOf()),
        throwsA(isA<AppFailure>().having((e) => e.message, 'message', contains('correo'))),
      );
      expect(staff.created, isEmpty);
    });

    test('datos inválidos no llegan al repositorio', () async {
      await expectLater(
        service.create(actorOf(UserRole.admin), draftOf(documento: '12')),
        throwsA(isA<AppFailure>()),
      );
      expect(staff.created, isEmpty);
    });

    test('una restricción vigente avisa pero NO bloquea la contratación', () async {
      restrictions.restrictions['87654321'] = const RehireRestriction(
        documento: '87654321', activa: true, revisarEn: '2027-01-01', establecidaPor: 's1',
      );
      final result = await service.create(actorOf(UserRole.admin), draftOf());
      expect(result.uid, isNotEmpty);
      expect(result.restriction, isNotNull);
      expect(staff.created, hasLength(1));
    });

    test('una restricción levantada no genera aviso', () async {
      restrictions.restrictions['87654321'] = const RehireRestriction(
        documento: '87654321', activa: false, revisarEn: '2027-01-01', establecidaPor: 's1',
      );
      final result = await service.create(actorOf(UserRole.admin), draftOf());
      expect(result.restriction, isNull);
    });

    test('baja exige tipo de motivo y texto de al menos 10 caracteres', () async {
      final admin = actorOf(UserRole.admin);
      final target = memberOf('m1');
      await expectLater(
        service.changeStatus(admin, target, const StatusChange(newStatus: StaffStatus.baja, detail: 'Motivo largo suficiente')),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.changeStatus(admin, target, const StatusChange(newStatus: StaffStatus.baja, reason: LeaveReason.despido, detail: 'corto')),
        throwsA(isA<AppFailure>()),
      );
      await service.changeStatus(admin, target,
          const StatusChange(newStatus: StaffStatus.baja, reason: LeaveReason.renuncia, detail: 'Renuncia voluntaria por estudios'));
      expect(staff.changes.single.$1, 'm1');
      expect(staff.changes.single.$2.reason, LeaveReason.renuncia);
    });

    test('una renuncia no puede registrarse como suspensión', () {
      expect(
        service.changeStatus(actorOf(UserRole.admin), memberOf('m1'),
            const StatusChange(newStatus: StaffStatus.suspendido, reason: LeaveReason.renuncia, detail: 'Motivo suficiente')),
        throwsA(isA<AppFailure>()),
      );
    });

    test('reactivar solo requiere el motivo escrito', () async {
      await service.changeStatus(
        actorOf(UserRole.admin),
        memberOf('m1', estado: StaffStatus.baja),
        const StatusChange(newStatus: StaffStatus.activo, detail: 'Retorna tras evaluación'),
      );
      expect(staff.changes.single.$2.isReactivation, isTrue);
    });

    test('no se puede cambiar al mismo estado', () {
      expect(
        service.changeStatus(actorOf(UserRole.admin), memberOf('m1'),
            const StatusChange(newStatus: StaffStatus.activo, detail: 'Motivo suficiente')),
        throwsA(isA<AppFailure>()),
      );
    });

    test('admin no puede dar de baja a otro admin ni a sí mismo', () async {
      const change = StatusChange(newStatus: StaffStatus.baja, reason: LeaveReason.otro, detail: 'Motivo suficiente');
      await expectLater(
        service.changeStatus(actorOf(UserRole.admin, uid: 'a1'), memberOf('a2', role: UserRole.admin), change),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.changeStatus(actorOf(UserRole.superadmin, uid: 's1'), memberOf('s1', role: UserRole.admin), change),
        throwsA(isA<AppFailure>()),
      );
      expect(staff.changes, isEmpty);
    });

    test('solo el superadmin autoriza regularizar, y solo a admins', () async {
      final admin = memberOf('a2', role: UserRole.admin);
      await expectLater(
        service.setRegularizationPermission(actorOf(UserRole.admin), admin, allowed: true),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.setRegularizationPermission(actorOf(UserRole.superadmin), memberOf('m1'), allowed: true),
        throwsA(isA<AppFailure>()),
      );
      await service.setRegularizationPermission(actorOf(UserRole.superadmin), admin, allowed: true);
      expect(staff.permissionChanges.single, ('a2', true));
    });
  });

  group('restricciones de recontratación', () {
    late FakeRestrictionRepository repo;
    late RestrictionService service;

    setUp(() {
      repo = FakeRestrictionRepository();
      service = RestrictionService(repo);
    });

    final today = DateTime(2026, 10, 26);
    final review = DateTime(2027, 4, 1);

    test('solo el superadmin establece, levanta o consulta la justificación', () async {
      final admin = actorOf(UserRole.admin);
      await expectLater(
        service.establish(admin, documento: '12345678', justification: 'Justificación válida', reviewOn: review, today: today),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(service.lift(admin, documento: '12345678', justification: 'Justificación válida'), throwsA(isA<AppFailure>()));
      await expectLater(() => service.justificationOf(admin, '12345678'), throwsA(isA<AppFailure>()));
      expect(repo.established, isEmpty);
    });

    test('exige justificación, documento válido y revisión futura', () async {
      final boss = actorOf(UserRole.superadmin);
      await expectLater(
        service.establish(boss, documento: '123', justification: 'Justificación válida', reviewOn: review, today: today),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.establish(boss, documento: '12345678', justification: 'corta', reviewOn: review, today: today),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        service.establish(boss, documento: '12345678', justification: 'Justificación válida', reviewOn: today, today: today),
        throwsA(isA<AppFailure>()),
      );
      await service.establish(boss, documento: '12345678', justification: 'Justificación válida', reviewOn: review, today: today);
      expect(repo.established, ['12345678']);
    });

    test('levantar exige justificación', () async {
      final boss = actorOf(UserRole.superadmin);
      await expectLater(service.lift(boss, documento: '12345678', justification: 'x'), throwsA(isA<AppFailure>()));
      await service.lift(boss, documento: '12345678', justification: 'Revisión favorable del caso');
      expect(repo.lifted, ['12345678']);
    });

    test('acepta carné de extranjería', () {
      expect(RestrictionService.validateDocument('abc123456'), isNull);
      expect(RestrictionService.validateDocument('12'), isNotNull);
    });

    test('marca la restricción para revisión cuando vence la fecha', () {
      const r = RehireRestriction(documento: '1', activa: true, revisarEn: '2026-10-01', establecidaPor: 's');
      expect(r.needsReview(DateTime(2026, 10, 26)), isTrue);
      expect(r.needsReview(DateTime(2026, 9, 1)), isFalse);
    });
  });

  group('lista: búsqueda, filtros y paginación de 20', () {
    final people = [
      for (var i = 0; i < 45; i++)
        memberOf('u$i',
            role: i.isEven ? UserRole.mesero : UserRole.cocina,
            estado: i % 5 == 0 ? StaffStatus.baja : StaffStatus.activo,
            documento: (10000000 + i).toString(),
            nombres: 'Nombre$i'.replaceAll(RegExp(r'\d'), 'x'),
            apellidos: 'Apellido${String.fromCharCode(65 + i % 26)}'),
    ];

    test('20 por página', () {
      const q = StaffListQuery();
      final all = q.filter(people);
      expect(StaffListQuery.pageSize, 20);
      expect(q.pageCount(all.length), 3);
      expect(q.pageOf(all), hasLength(20));
      expect(q.copyWith(page: 2).pageOf(all), hasLength(5));
      expect(q.copyWith(page: 99).pageOf(all), hasLength(5)); // se ajusta
    });

    test('filtra por rol y estado', () {
      final cocina = const StaffListQuery().copyWith(role: () => UserRole.cocina).filter(people);
      expect(cocina.every((m) => m.role == UserRole.cocina), isTrue);
      final bajas = const StaffListQuery().copyWith(status: () => StaffStatus.baja).filter(people);
      expect(bajas, hasLength(9));
    });

    test('busca por documento, sin distinguir tildes ni mayúsculas', () {
      expect(const StaffListQuery(text: '10000007').filter(people), hasLength(1));
      final ana = [memberOf('x', nombres: 'José', apellidos: 'Muñoz')];
      expect(const StaffListQuery(text: 'jose muno').filter(ana), hasLength(1));
    });

    test('incluye personal inactivo en los resultados', () {
      expect(const StaffListQuery(text: '10000000').filter(people).single.estado, StaffStatus.baja);
    });
  });

  test('un perfil de la Fase 2 (superadmin) se lista como ficha incompleta, no se oculta', () {
    final legacy = StaffMember.fromMap('uid-super', {
      'email': 'sprad@granjaazul.com',
      'nombre': 'AdGjAzul',
      'rol': 'superadmin',
      'activo': true,
    })!;
    expect(legacy.incompleto, isTrue);
    expect(legacy.activo, isTrue);
    expect(legacy.role, UserRole.superadmin);
    expect(legacy.nombreCompleto.trim(), 'AdGjAzul');
    expect(const StaffListQuery().filter([legacy]), hasLength(1));
    expect(legacy.documentoEnmascarado, isEmpty);
  });

  test('StaffMember ignora documentos con rol inválido', () {
    expect(StaffMember.fromMap('u', {'rol': 'dios'}), isNull);
    expect(
      StaffMember.fromMap('u', {
        'rol': 'mesero', 'tipoDocumento': 'dni', 'numeroDocumento': '12345678',
        'estado': 'baja', 'activo': false, 'fechaIngreso': '2026-01-15',
      })!.activo,
      isFalse,
    );
  });
}
