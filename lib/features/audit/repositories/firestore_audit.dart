import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../users/models/app_user.dart';
import '../models/audit_entry.dart';
import 'audit_repository.dart';

/// Agrega un registro de auditoría a un lote de escrituras. Devuelve su id,
/// que el documento afectado referencia (`ultimaAuditoriaId`) para que las
/// reglas exijan que ninguna acción administrativa quede sin rastro.
String addAuditEntry(
  FirebaseFirestore firestore,
  WriteBatch batch, {
  required AppUser actor,
  required String accion,
  required String objetivo,
  List<String> campos = const [],
}) {
  final ref = firestore.collection(FirestorePaths.auditoria).doc();
  batch.set(ref, {
    'accion': accion,
    'actorUid': actor.uid,
    'actorNombre': actor.nombre,
    'objetivo': objetivo,
    'campos': campos,
    'creadoEn': FieldValue.serverTimestamp(),
  });
  return ref.id;
}

class FirestoreAuditRepository implements AuditRepository {
  FirestoreAuditRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 100}) => _firestore
      .collection(FirestorePaths.auditoria)
      .orderBy('creadoEn', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) AuditEntry.fromMap(d.id, d.data())]);
}
