import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../audit/models/audit_entry.dart';
import '../../audit/repositories/firestore_audit.dart';
import '../../users/models/app_user.dart';
import '../models/rehire_restriction.dart';
import '../models/staff_member.dart';
import 'staff_repository.dart';

/// `restricciones/{documento}` guarda estado y fechas (visible para admins);
/// la justificación vive en `restricciones/{documento}/privado/detalle`, solo
/// legible por el Superadmin.
class FirestoreRestrictionRepository implements RestrictionRepository {
  FirestoreRestrictionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String documento) =>
      _firestore.collection(FirestorePaths.restricciones).doc(documento);

  @override
  Future<RehireRestriction?> find(String documento) async {
    final snap = await _doc(documento).get();
    final data = snap.data();
    return data == null ? null : RehireRestriction.fromMap(snap.id, data);
  }

  @override
  Stream<List<RehireRestriction>> watchAll() => _firestore
      .collection(FirestorePaths.restricciones)
      .snapshots()
      .map((s) => [
            for (final d in s.docs) RehireRestriction.fromMap(d.id, d.data()),
          ]);

  @override
  Future<String?> readJustification(String documento) async {
    final snap =
        await _doc(documento).collection('privado').doc('detalle').get();
    return snap.data()?['justificacion'] as String?;
  }

  @override
  Future<void> set({
    required String documento,
    required String justification,
    required DateTime reviewOn,
    required AppUser actor,
  }) =>
      _write(
        documento,
        actor,
        AuditAction.crearRestriccion,
        estado: 'activa',
        justification: justification,
        reviewOn: reviewOn,
      );

  @override
  Future<void> lift({
    required String documento,
    required String justification,
    required AppUser actor,
  }) =>
      _write(
        documento,
        actor,
        AuditAction.levantarRestriccion,
        estado: 'levantada',
        justification: justification,
      );

  Future<void> _write(
    String documento,
    AppUser actor,
    String action, {
    required String estado,
    required String justification,
    DateTime? reviewOn,
  }) async {
    final batch = _firestore.batch();
    final auditId = addAuditEntry(_firestore, batch,
        actor: actor, accion: action, objetivo: documento);
    batch.set(
      _doc(documento),
      {
        'estado': estado,
        'establecidaPor': actor.uid,
        'actualizadoEn': FieldValue.serverTimestamp(),
        if (reviewOn != null) 'revisarEn': StaffMember.formatDate(reviewOn),
        'ultimaAuditoriaId': auditId,
      },
      SetOptions(merge: true),
    );
    batch.set(_doc(documento).collection('privado').doc('detalle'), {
      'justificacion': justification.trim(),
      'actorUid': actor.uid,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
