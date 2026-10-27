import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/attendance/models/attendance_models.dart';
import 'package:granja_azul/features/attendance/repositories/attendance_repositories.dart';
import 'package:granja_azul/features/attendance/services/terminal_binding.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/staff/models/document_type.dart';
import 'package:granja_azul/features/staff/models/rehire_restriction.dart';
import 'package:granja_azul/features/staff/models/staff_draft.dart';
import 'package:granja_azul/features/staff/models/staff_member.dart';
import 'package:granja_azul/features/staff/models/staff_status.dart';
import 'package:granja_azul/features/staff/models/status_change.dart';
import 'package:granja_azul/features/staff/repositories/staff_repository.dart';
import 'package:granja_azul/features/users/models/app_user.dart';

AppUser actorOf(UserRole role, {String uid = 'actor', bool regularize = false}) =>
    AppUser(
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
}) =>
    StaffMember(
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
}) =>
    StaffDraft(
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
  Future<CreatedStaff> create(StaffDraft draft, {required AppUser actor}) async {
    created.add(draft);
    documents.add(draft.documentoNormalizado);
    emails.add(draft.emailNormalizado);
    return CreatedStaff('uid-${created.length}',
        resetEmailSent: resetEmailSent, verificationSent: verificationSent);
  }

  @override
  Future<void> update(StaffMember current, StaffDraft draft,
      {required AppUser actor}) async {}

  @override
  Future<void> changeStatus(StaffMember target, StatusChange change,
      {required AppUser actor}) async {
    changes.add((target.uid, change));
  }

  @override
  Future<void> setRegularizationPermission(StaffMember target,
      {required bool allowed, required AppUser actor}) async {
    permissionChanges.add((target.uid, allowed));
  }

  @override
  Future<void> assignSchedule(StaffMember target, String? scheduleId,
      {required AppUser actor}) async {}
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
  final tokensCreated = <(PunchType, String)>[];
  final corrections = <String>[];

  @override
  Future<QrToken> createToken(AppUser worker, PunchType type, String tokenId) async {
    tokensCreated.add((type, tokenId));
    return QrToken(
      id: tokenId,
      uid: worker.uid,
      tipo: type,
      nombreMostrar: worker.nombres,
      creadoEn: DateTime.now(),
      usadoEn: null,
    );
  }

  @override
  Stream<QrToken?> watchToken(String tokenId) => Stream.value(null);

  @override
  Stream<AttendanceState?> watchState(String uid) => Stream.value(null);

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

/// Simula al servidor: aplica las mismas reglas que `firestore.rules`.
class FakeTerminalScanRepository implements TerminalScanRepository {
  final tokens = <String, QrToken>{};
  final states = <String, AttendanceState>{};
  final commits = <String>[];

  /// Secreto registrado en el servidor (`terminalClaves`); lo comparan las reglas.
  String? enrolledKey;

  /// Si es `true`, el servidor rechaza la escritura (QR vencido, etc.).
  bool serverRejects = false;
  DateTime serverTime = DateTime.utc(2026, 10, 26, 13, 0);

  @override
  Future<QrToken?> fetchToken(String tokenId) async => tokens[tokenId];

  @override
  Future<AttendanceState?> fetchState(String uid) async => states[uid];

  @override
  Future<void> enroll({required String terminalUid, required String key}) async {
    if (enrolledKey != null) {
      throw const AppFailure('ya enlazada', code: 'permission-denied');
    }
    enrolledKey = key;
  }

  @override
  Future<DateTime> commit({
    required QrToken token,
    required AttendanceState? state,
    required String terminalUid,
    required String deviceKey,
  }) async {
    if (serverRejects || (enrolledKey != null && deviceKey != enrolledKey)) {
      throw const AppFailure('rechazado', code: 'permission-denied');
    }
    final live = tokens[token.id]!;
    if (live.used) {
      throw const AppFailure('usado', code: 'permission-denied');
    }
    tokens[token.id] = QrToken(
      id: live.id,
      uid: live.uid,
      tipo: live.tipo,
      nombreMostrar: live.nombreMostrar,
      creadoEn: live.creadoEn,
      usadoEn: serverTime,
    );
    states[token.uid] = AttendanceState(
      abierta: token.tipo == PunchType.entrada,
      asistenciaId: 'asis-${commits.length}',
    );
    commits.add('${token.tipo.value}:${token.uid}');
    return serverTime;
  }
}

class FakeTerminalRepository implements TerminalRepository {
  final terminals = <String, AttendanceTerminal>{};

  @override
  Stream<AttendanceTerminal?> watchTerminal(String uid) =>
      Stream.value(terminals[uid]);

  @override
  Stream<List<AttendanceTerminal>> watchAll() =>
      Stream.value(terminals.values.toList());

  @override
  Future<void> authorize(AppUser actor,
      {required String nombre, required String uid}) async {
    terminals[uid] = AttendanceTerminal(uid: uid, nombre: nombre, activo: true);
  }

  @override
  Future<void> setActive(AppUser actor, AttendanceTerminal terminal,
      {required bool active}) async {
    terminals[terminal.uid] =
        AttendanceTerminal(uid: terminal.uid, nombre: terminal.nombre, activo: active);
  }

  final resets = <String>[];

  @override
  Future<void> resetDeviceLink(AppUser actor, AttendanceTerminal terminal) async {
    resets.add(terminal.uid);
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

class FakeDeviceKeyStore implements DeviceKeyStore {
  FakeDeviceKeyStore([Map<String, String>? initial]) : keys = {...?initial};

  final Map<String, String> keys;

  @override
  Future<String?> read(String terminalUid) async => keys[terminalUid];

  @override
  Future<void> write(String terminalUid, String key) async => keys[terminalUid] = key;

  @override
  Future<void> clear(String terminalUid) async => keys.remove(terminalUid);
}
