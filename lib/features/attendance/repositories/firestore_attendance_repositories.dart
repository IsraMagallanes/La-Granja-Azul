import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../audit/models/audit_entry.dart';
import '../../audit/repositories/firestore_audit.dart';
import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import 'attendance_repositories.dart';

CollectionReference<Map<String, dynamic>> _col(
  FirebaseFirestore db,
  String name,
) => db.collection(name);

class FirestoreWorkerAttendanceRepository
    implements WorkerAttendanceRepository {
  FirestoreWorkerAttendanceRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<AttendanceState?> watchState(String uid) =>
      _col(_db, FirestorePaths.estadoAsistencia)
          .doc(uid)
          .snapshots()
          .map(
            (d) => d.data() == null ? null : AttendanceState.fromMap(d.data()!),
          );

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
          .map(
            (s) => [
              for (final d in s.docs) CorrectionRequest.fromMap(d.id, d.data()),
            ]..sort((a, b) => b.fecha.compareTo(a.fecha)),
          );

  @override
  Future<void> requestCorrection({
    required String uid,
    required String fecha,
    required String tipo,
    required String motivo,
  }) => _col(_db, FirestorePaths.correcciones).add({
    'uid': uid,
    'fecha': fecha,
    'tipo': tipo,
    'motivo': motivo.trim(),
    'estado': CorrectionStatus.pendiente.value,
    'creadoEn': FieldValue.serverTimestamp(),
  });
}

List<AttendanceRecord> _records(QuerySnapshot<Map<String, dynamic>> s) => [
  for (final d in s.docs) ?AttendanceRecord.fromMap(d.id, d.data()),
];

class FirestoreQrGenerationRepository implements QrGenerationRepository {
  FirestoreQrGenerationRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<QrToken> createToken(AppUser generator, String tokenId) async {
    final ref = _col(_db, FirestorePaths.qrTokens).doc(tokenId);
    // `nombreMostrar` (solo nombres de pila) y `generadorRol` los valida la
    // regla contra el perfil; el QR en sí únicamente contiene el id del token.
    await ref.set({
      'generadorUid': generator.uid,
      'generadorRol': generator.role.value,
      'nombreMostrar': generator.nombres,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    final snap = await ref.get();
    return QrToken.fromMap(tokenId, snap.data()!)!;
  }
}

class FirestoreQrScanRepository implements QrScanRepository {
  FirestoreQrScanRepository(this._db);

  final FirebaseFirestore _db;

  @override
  Future<QrToken?> fetchToken(String tokenId) async {
    final snap = await _col(_db, FirestorePaths.qrTokens).doc(tokenId).get();
    final data = snap.data();
    return data == null ? null : QrToken.fromMap(snap.id, data);
  }

  @override
  Future<AttendanceState?> fetchState(String uid) async {
    final snap = await _col(
      _db,
      FirestorePaths.estadoAsistencia,
    ).doc(uid).get();
    final data = snap.data();
    return data == null ? null : AttendanceState.fromMap(data);
  }

  @override
  Future<DateTime> commit({
    required QrToken token,
    required String uid,
    required PunchType type,
    required AttendanceState? state,
  }) async {
    final stateRef = _col(_db, FirestorePaths.estadoAsistencia).doc(uid);
    final records = _col(_db, FirestorePaths.asistencias);
    final batch = _db.batch();
    final String recordId;

    // Un único lote: registro + estado, con la hora del servidor. Si cualquier
    // regla falla, no se escribe nada.
    if (type == PunchType.entrada) {
      final recordRef = records.doc();
      recordId = recordRef.id;
      batch.set(recordRef, {
        'uid': uid,
        'entrada': FieldValue.serverTimestamp(),
        'salida': null,
        'origen': AttendanceOrigin.qr.value,
        'tokenId': token.id,
        'regularizada': false,
      });
      batch.set(stateRef, {
        'abierta': true,
        'asistenciaId': recordId,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'tokenId': token.id,
      });
    } else {
      recordId = state!.asistenciaId!;
      batch.update(records.doc(recordId), {
        'salida': FieldValue.serverTimestamp(),
        'salidaTokenId': token.id,
      });
      batch.set(stateRef, {
        'abierta': false,
        'asistenciaId': recordId,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'tokenId': token.id,
      });
    }
    await batch.commit();

    final saved = (await records.doc(recordId).get()).data();
    final raw = saved?[type == PunchType.entrada ? 'entrada' : 'salida'];
    return raw is Timestamp ? raw.toDate() : DateTime.now();
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
  Stream<List<Schedule>> watchSchedules() => _col(_db, FirestorePaths.horarios)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?Schedule.fromMap(d.id, d.data())]);

  @override
  Future<void> saveSchedule(AppUser actor, Schedule schedule) async {
    final ref = schedule.id.isEmpty
        ? _col(_db, FirestorePaths.horarios).doc()
        : _col(_db, FirestorePaths.horarios).doc(schedule.id);
    final batch = _db.batch();
    final auditId = addAuditEntry(
      _db,
      batch,
      actor: actor,
      accion: AuditAction.guardarHorario,
      objetivo: ref.id,
    );
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
    final auditId = addAuditEntry(
      _db,
      batch,
      actor: actor,
      accion: AuditAction.regularizarAsistencia,
      objetivo: uid,
      campos: ['entrada', if (salida != null) 'salida'],
    );
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
    final auditId = addAuditEntry(
      _db,
      batch,
      actor: actor,
      accion: AuditAction.regularizarAsistencia,
      objetivo: record.uid,
      campos: [
        if (entrada != record.entrada) 'entrada',
        if (salida != record.salida) 'salida',
      ],
    );
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
      _col(_db, FirestorePaths.correcciones).snapshots().map(
        (s) =>
            [for (final d in s.docs) CorrectionRequest.fromMap(d.id, d.data())]
              ..sort((a, b) => b.fecha.compareTo(a.fecha)),
      );

  @override
  Future<void> resolveCorrection(
    AppUser actor,
    CorrectionRequest request, {
    required bool approved,
    required String respuesta,
  }) async {
    final batch = _db.batch();
    final auditId = addAuditEntry(
      _db,
      batch,
      actor: actor,
      accion: AuditAction.resolverCorreccion,
      objetivo: request.uid,
    );
    batch.update(_col(_db, FirestorePaths.correcciones).doc(request.id), {
      'estado':
          (approved ? CorrectionStatus.aprobada : CorrectionStatus.rechazada)
              .value,
      'respuesta': respuesta.trim(),
      'resueltoPor': actor.uid,
      'resueltoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    await batch.commit();
  }
}

