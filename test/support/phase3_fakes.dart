import 'dart:async';

import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/attendance/repositories/attendance_repositories.dart';
import 'package:granja_azul/features/attendance/services/scan_validator.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/models/document_type.dart';
import 'package:granja_azul/features/staff/models/rehire_restriction.dart';
import 'package:granja_azul/features/staff/models/staff_draft.dart';
import 'package:granja_azul/features/staff/models/staff_member.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/models/status_change.dart';
import 'package:granja_azul/features/staff/repositories/staff_repository.dart';
import 'package:granja_azul/features/users/models/app_user.dart';

AppUser actorOf(
  UserRole role, {
  String uid = 'actor',
  bool regularize = false,
}) => AppUser(
  uid: uid,
  email: '$uid@granja.pe',
  nombre: 'Actor $uid',
  nombres: 'Actor',
  role: role,
  activo: true,
  puedeRegularizar: regularize,
);

StaffMember memberOf(
  String uid, {
  UserRole role = UserRole.mesero,
  StaffStatus estado = StaffStatus.activo,
  String documento = '12345678',
  String? horarioId,
  String nombres = 'Ana',
  String apellidos = 'Pérez',
}) => StaffMember(
  uid: uid,
  nombres: nombres,
  apellidos: apellidos,
  documentType: DocumentType.dni,
  documento: documento,
  email: '$uid@granja.pe',
  celular: '987654321',
  role: role,
  estado: estado,
  fechaIngreso: DateTime(2026, 1, 15),
  horarioId: horarioId,
);

StaffDraft draftOf({
  UserRole role = UserRole.mesero,
  String documento = '87654321',
  String email = 'nuevo@granja.pe',
  DocumentType type = DocumentType.dni,
  String celular = '912345678',
  String? alterno,
}) => StaffDraft(
  nombres: 'Luis',
  apellidos: 'Gómez',
  documentType: type,
  documento: documento,
  email: email,
  celular: celular,
  celularAlterno: alterno,
  role: role,
  fechaIngreso: DateTime(2026, 2, 1),
);

class FakeStaffRepository implements StaffRepository {
  final members = <StaffMember>[];
  final documents = <String>{};
  final emails = <String>{};
  final changes = <(String, StatusChange)>[];
  final created = <StaffDraft>[];
  final permissionChanges = <(String, bool)>[];
  bool resetEmailSent = true;
  bool verificationSent = true;

  @override
  Stream<List<StaffMember>> watchAll() => Stream.value(members);

  @override
  Future<bool> documentExists(String documento) async =>
      documents.contains(documento);

  @override
  Future<bool> emailExists(String email) async => emails.contains(email);

  @override
  Future<CreatedStaff> create(
    StaffDraft draft, {
    required AppUser actor,
  }) async {
    created.add(draft);
    documents.add(draft.documentoNormalizado);
    emails.add(draft.emailNormalizado);
    return CreatedStaff(
      'uid-${created.length}',
      resetEmailSent: resetEmailSent,
      verificationSent: verificationSent,
    );
  }

  @override
  Future<void> update(
    StaffMember current,
    StaffDraft draft, {
    required AppUser actor,
  }) async {}

  @override
  Future<void> changeStatus(
    StaffMember target,
    StatusChange change, {
    required AppUser actor,
  }) async {
    changes.add((target.uid, change));
  }

  @override
  Future<void> setRegularizationPermission(
    StaffMember target, {
    required bool allowed,
    required AppUser actor,
  }) async {
    permissionChanges.add((target.uid, allowed));
  }

  @override
  Future<void> assignSchedule(
    StaffMember target,
    String? scheduleId, {
    required AppUser actor,
  }) async {}
}

class FakeRestrictionRepository implements RestrictionRepository {
  final restrictions = <String, RehireRestriction>{};
  final established = <String>[];
  final lifted = <String>[];

  @override
  Future<RehireRestriction?> find(String documento) async =>
      restrictions[documento];

  @override
  Stream<List<RehireRestriction>> watchAll() =>
      Stream.value(restrictions.values.toList());

  @override
  Future<String?> readJustification(String documento) async => 'secreto';

  @override
  Future<void> set({
    required String documento,
    required String justification,
    required DateTime reviewOn,
    required AppUser actor,
  }) async {
    established.add(documento);
  }

  @override
  Future<void> lift({
    required String documento,
    required String justification,
    required AppUser actor,
  }) async {
    lifted.add(documento);
  }
}

class FakeWorkerAttendanceRepository implements WorkerAttendanceRepository {
  final corrections = <String>[];

  /// Estado de jornada por trabajador (`estadoAsistencia/{uid}`).
  final states = <String, AttendanceState>{};
  final _stateChanges = StreamController<void>.broadcast();

  /// Simula que el trabajador registró la entrada (`open`) o la salida.
  void setShift(String uid, {required bool open}) {
    states[uid] = AttendanceState(abierta: open, asistenciaId: 'a-$uid');
    _stateChanges.add(null);
  }

  @override
  Stream<AttendanceState?> watchState(String uid) async* {
    yield states[uid];
    await for (final _ in _stateChanges.stream) {
      yield states[uid];
    }
  }

  @override
  Stream<List<AttendanceRecord>> watchHistory(String uid, {int limit = 30}) =>
      Stream.value(const []);

  @override
  Stream<List<CorrectionRequest>> watchCorrections(String uid) =>
      Stream.value(const []);

  @override
  Future<void> requestCorrection({
    required String uid,
    required String fecha,
    required String tipo,
    required String motivo,
  }) async {
    corrections.add(motivo);
  }
}

/// Generación de QR en memoria.
class FakeQrGenerationRepository implements QrGenerationRepository {
  final created = <QrToken>[];

  @override
  Future<QrToken> createToken(AppUser generator, String tokenId) async {
    final token = QrToken(
      id: tokenId,
      generadorUid: generator.uid,
      generadorRol: generator.role,
      nombreMostrar: generator.nombres,
      creadoEn: DateTime.now(),
    );
    created.add(token);
    return token;
  }
}

/// Simula al servidor del escaneo: aplica las mismas reglas que
/// `firestore.rules` (el generador permitido para el rol del escáner, un QR no
/// encadenado, entrada única y salida con entrada abierta).
class FakeQrScanRepository implements QrScanRepository {
  final tokens = <String, QrToken>{};
  final states = <String, AttendanceState>{};
  final commits = <String>[];

  /// Roles de los escáneres (el servidor los conoce por el perfil).
  final roles = <String, UserRole>{};

  /// Si es `true`, el servidor rechaza la escritura (QR vencido, etc.).
  bool serverRejects = false;
  DateTime serverTime = DateTime.utc(2026, 10, 26, 13, 0);

  @override
  Future<QrToken?> fetchToken(String tokenId) async => tokens[tokenId];

  @override
  Future<AttendanceState?> fetchState(String uid) async => states[uid];

  @override
  Future<DateTime> commit({
    required QrToken token,
    required String uid,
    required PunchType type,
    required AttendanceState? state,
  }) async {
    final role = roles[uid];
    final stored = states[uid];
    final open = stored?.abierta ?? false;
    if (serverRejects ||
        role == null ||
        !const QrPolicy().canScanFrom(role, token.generadorRol) ||
        token.generadorUid == uid ||
        stored?.tokenId == token.id ||
        (type == PunchType.entrada) == open) {
      throw const AppFailure('rechazado', code: 'permission-denied');
    }
    states[uid] = AttendanceState(
      abierta: type == PunchType.entrada,
      asistenciaId: stored?.asistenciaId ?? 'asis-${commits.length}',
      tokenId: token.id,
    );
    commits.add('${type.value}:$uid');
    return serverTime;
  }
}

class FakePendingAccount implements PendingAccount {
  FakePendingAccount(this.uid);

  @override
  final String uid;
  bool committed = false;
  bool rolledBack = false;

  @override
  Future<ActivationMail> commit() async {
    committed = true;
    return const ActivationMail();
  }

  @override
  Future<void> rollback() async => rolledBack = true;
}

class FakeAccountCreator implements StaffAccountCreator {
  final created = <(String, String?)>[];
  final accounts = <FakePendingAccount>[];

  @override
  Future<PendingAccount> createAccount(String email, {String? password}) async {
    created.add((email, password));
    final account = FakePendingAccount('term-${created.length}');
    accounts.add(account);
    return account;
  }
}
