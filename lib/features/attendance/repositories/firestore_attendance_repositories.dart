import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../audit/models/audit_entry.dart';
import '../../audit/repositories/firestore_audit.dart';
import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import 'attendance_repositories.dart';

CollectionReference<Map<String, dynamic>> _col(
        FirebaseFirestore db, String name) =>
    db.collection(name);

class FirestoreWorkerAttendanceRepository
    implements WorkerAttendanceRepository {
  FirestoreWorkerAttendanceRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<QrToken> createToken(
      AppUser worker, PunchType type, String tokenId) async {
    final ref = _col(_db, FirestorePaths.qrTokens).doc(tokenId);
    // `nombreMostrar` (solo nombres de pila) lo valida la regla contra el
    // perfil; el QR en sí únicamente contiene el id del token.
    await ref.set({
      'uid': worker.uid,
      'tipo': type.value,
      'nombreMostrar': worker.nombres,
      'creadoEn': FieldValue.serverTimestamp(),
      'usadoEn': null,
      'terminalId': null,
    });
    final snap = await ref.get();
    return QrToken.fromMap(tokenId, snap.data()!)!;
  }

  @override
  Stream<QrToken?> watchToken(String tokenId) => _col(_db, FirestorePaths.qrTokens)
      .doc(tokenId)
      .snapshots()
      .map((d) => d.data() == null ? null : QrToken.fromMap(d.id, d.data()!));

  @override
  Stream<AttendanceState?> watchState(String uid) =>
      _col(_db, FirestorePaths.estadoAsistencia).doc(uid).snapshots().map(
          (d) => d.data() == null ? null : AttendanceState.fromMap(d.data()!));

  @override
  Stream<List<AttendanceRecord>> watchHistory(String uid, {int limit = 30}) =>
      _col(_db, FirestorePaths.asistencias)
          .where('uid', isEqualTo: uid)
          .orderBy('entrada', descending: true)
          .limit(limit)
          .snapshots()
          .map(_records);

  @override
  Stream<List<CorrectionRequest>> watchCorrections(String uid) =>
      _col(_db, FirestorePaths.correcciones)
          .where('uid', isEqualTo: uid)
          .snapshots()
          .map((s) => [
                for (final d in s.docs) CorrectionRequest.fromMap(d.id, d.data()),
              ]..sort((a, b) => b.fecha.compareTo(a.fecha)));

  @override
  Future<void> requestCorrection({
    required String uid,
    required String fecha,
    required String tipo,
    required String motivo,
  }) =>
      _col(_db, FirestorePaths.correcciones).add({
        'uid': uid,
        'fecha': fecha,
        'tipo': tipo,
        'motivo': motivo.trim(),
        'estado': CorrectionStatus.pendiente.value,
        'creadoEn': FieldValue.serverTimestamp(),
      });
}

List<AttendanceRecord> _records(QuerySnapshot<Map<String, dynamic>> s) => [
      for (final d in s.docs)
        ?AttendanceRecord.fromMap(d.id, d.data()),
    ];

class FirestoreTerminalScanRepository implements TerminalScanRepository {
  FirestoreTerminalScanRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<QrToken?> fetchToken(String tokenId) async {
    final snap = await _col(_db, FirestorePaths.qrTokens).doc(tokenId).get();
    final data = snap.data();
    return data == null ? null : QrToken.fromMap(snap.id, data);
  }

  @override
  Future<AttendanceState?> fetchState(String uid) async {
    final snap = await _col(_db, FirestorePaths.estadoAsistencia).doc(uid).get();
    final data = snap.data();
    return data == null ? null : AttendanceState.fromMap(data);
  }

  @override
  Future<void> enroll({required String terminalUid, required String key}) =>
      _col(_db, FirestorePaths.terminalClaves).doc(terminalUid).set({
        'clave': key,
        'creadoEn': FieldValue.serverTimestamp(),
      });

  @override
  Future<DateTime> commit({
    required QrToken token,
    required AttendanceState? state,
    required String terminalUid,
    required String deviceKey,
  }) async {
    final tokenRef = _col(_db, FirestorePaths.qrTokens).doc(token.id);
    final stateRef = _col(_db, FirestorePaths.estadoAsistencia).doc(token.uid);
    final records = _col(_db, FirestorePaths.asistencias);
    final batch = _db.batch();

    // Un único lote: token consumido + registro + estado, todos con la hora
    // del servidor. Si cualquier regla falla, no se escribe nada.
    batch.set(_col(_db, FirestorePaths.terminalPruebas).doc(terminalUid), {
      'clave': deviceKey,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
    batch.update(tokenRef, {
      'usadoEn': FieldValue.serverTimestamp(),
      'terminalId': terminalUid,
    });
    if (token.tipo == PunchType.entrada) {
      final recordRef = records.doc();
      batch.set(recordRef, {
        'uid': token.uid,
        'entrada': FieldValue.serverTimestamp(),
        'salida': null,
        'origen': AttendanceOrigin.qr.value,
        'terminalId': terminalUid,
        'tokenId': token.id,
        'regularizada': false,
      });
      batch.set(stateRef, {
        'abierta': true,
        'asistenciaId': recordRef.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    } else {
      final recordId = state!.asistenciaId!;
      batch.update(records.doc(recordId), {
        'salida': FieldValue.serverTimestamp(),
        'salidaTokenId': token.id,
      });
      batch.set(stateRef, {
        'abierta': false,
        'asistenciaId': recordId,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    final used = await fetchToken(token.id);
    return used?.usadoEn ?? DateTime.now();
  }
}

class FirestoreAttendanceAdminRepository implements AttendanceAdminRepository {
  FirestoreAttendanceAdminRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<List<AttendanceRecord>> watchRange(DateTime from, DateTime to) =>
      _col(_db, FirestorePaths.asistencias)
          .where('entrada', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('entrada', isLessThan: Timestamp.fromDate(to))
          .orderBy('entrada', descending: true)
          .snapshots()
          .map(_records);

  @override
  Stream<List<Schedule>> watchSchedules() =>
      _col(_db, FirestorePaths.horarios).snapshots().map((s) => [
            for (final d in s.docs)
              ?Schedule.fromMap(d.id, d.data()),
          ]);

  @override
  Future<void> saveSchedule(AppUser actor, Schedule schedule) async {
    final ref = schedule.id.isEmpty
        ? _col(_db, FirestorePaths.horarios).doc()
        : _col(_db, FirestorePaths.horarios).doc(schedule.id);
    final batch = _db.batch();
    final auditId = addAuditEntry(_db, batch,
        actor: actor, accion: AuditAction.guardarHorario, objetivo: ref.id);
    batch.set(ref, {
      ...schedule.toMap(),
      'actualizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    await batch.commit();
  }

  @override
  Future<void> regularizeCreate(
    AppUser actor, {
    required String uid,
    required DateTime entrada,
    required DateTime? salida,
    required AttendanceOrigin origin,
    required String motivo,
  }) async {
    final batch = _db.batch();
    final auditId = addAuditEntry(_db, batch,
        actor: actor,
        accion: AuditAction.regularizarAsistencia,
        objetivo: uid,
        campos: ['entrada', if (salida != null) 'salida']);
    final ref = _col(_db, FirestorePaths.asistencias).doc();
    batch.set(ref, {
      'uid': uid,
      'entrada': Timestamp.fromDate(entrada),
      'salida': salida == null ? null : Timestamp.fromDate(salida),
      'origen': origin.value,
      'regularizada': true,
      'motivo': motivo.trim(),
      'regularizadoPor': actor.uid,
      'regularizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    if (salida == null) {
      batch.set(_col(_db, FirestorePaths.estadoAsistencia).doc(uid), {
        'abierta': true,
        'asistenciaId': ref.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'regularizadoPor': actor.uid,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> regularizeUpdate(
    AppUser actor, {
    required AttendanceRecord record,
    required DateTime entrada,
    required DateTime? salida,
    required String motivo,
    required bool closesOpenState,
  }) async {
    final batch = _db.batch();
    final auditId = addAuditEntry(_db, batch,
        actor: actor,
        accion: AuditAction.regularizarAsistencia,
        objetivo: record.uid,
        campos: [
          if (entrada != record.entrada) 'entrada',
          if (salida != record.salida) 'salida',
        ]);
    batch.update(_col(_db, FirestorePaths.asistencias).doc(record.id), {
      'entrada': Timestamp.fromDate(entrada),
      'salida': salida == null ? null : Timestamp.fromDate(salida),
      'regularizada': true,
      'motivo': motivo.trim(),
      'regularizadoPor': actor.uid,
      'regularizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    if (closesOpenState) {
      batch.set(_col(_db, FirestorePaths.estadoAsistencia).doc(record.uid), {
        'abierta': false,
        'asistenciaId': record.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'regularizadoPor': actor.uid,
      });
    }
    await batch.commit();
  }

  @override
  Stream<List<CorrectionRequest>> watchAllCorrections() =>
      _col(_db, FirestorePaths.correcciones).snapshots().map((s) => [
            for (final d in s.docs) CorrectionRequest.fromMap(d.id, d.data()),
          ]..sort((a, b) => b.fecha.compareTo(a.fecha)));

  @override
  Future<void> resolveCorrection(
    AppUser actor,
    CorrectionRequest request, {
    required bool approved,
    required String respuesta,
  }) async {
    final batch = _db.batch();
    final auditId = addAuditEntry(_db, batch,
        actor: actor,
        accion: AuditAction.resolverCorreccion,
        objetivo: request.uid);
    batch.update(_col(_db, FirestorePaths.correcciones).doc(request.id), {
      'estado': (approved ? CorrectionStatus.aprobada : CorrectionStatus.rechazada)
          .value,
      'respuesta': respuesta.trim(),
      'resueltoPor': actor.uid,
      'resueltoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    await batch.commit();
  }
}

class FirestoreTerminalRepository implements TerminalRepository {
  FirestoreTerminalRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<AttendanceTerminal?> watchTerminal(String uid) =>
      _col(_db, FirestorePaths.terminales).doc(uid).snapshots().map((d) =>
          d.data() == null ? null : AttendanceTerminal.fromMap(d.id, d.data()!));

  @override
  Stream<List<AttendanceTerminal>> watchAll() =>
      _col(_db, FirestorePaths.terminales).snapshots().map((s) => [
            for (final d in s.docs) AttendanceTerminal.fromMap(d.id, d.data()),
          ]);

  @override
  Future<void> authorize(AppUser actor,
          {required String nombre, required String uid}) =>
      _write(actor, uid, nombre, true, AuditAction.autorizarTerminal);

  @override
  Future<void> setActive(AppUser actor, AttendanceTerminal terminal,
          {required bool active}) =>
      _write(actor, terminal.uid, terminal.nombre, active,
          active ? AuditAction.autorizarTerminal : AuditAction.revocarTerminal);

  @override
  Future<void> resetDeviceLink(AppUser actor, AttendanceTerminal terminal) {
    final batch = _db.batch();
    addAuditEntry(_db, batch,
        actor: actor, accion: AuditAction.restablecerTerminal, objetivo: terminal.uid);
    batch.delete(_col(_db, FirestorePaths.terminalClaves).doc(terminal.uid));
    return batch.commit();
  }

  Future<void> _write(
      AppUser actor, String uid, String nombre, bool active, String action) {
    final batch = _db.batch();
    final auditId = addAuditEntry(_db, batch,
        actor: actor, accion: action, objetivo: uid);
    batch.set(_col(_db, FirestorePaths.terminales).doc(uid), {
      'nombre': nombre.trim(),
      'activo': active,
      'autorizadoPor': actor.uid,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    return batch.commit();
  }
}
