import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../audit/models/audit_entry.dart';
import '../../audit/repositories/firestore_audit.dart';
import '../../users/models/app_user.dart';
import '../models/staff_draft.dart';
import '../models/staff_member.dart';
import '../models/staff_status.dart';
import '../models/status_change.dart';
import 'staff_repository.dart';

/// Persistencia de personal. Cada operación es un lote atómico que incluye su
/// registro de auditoría; `firestore.rules` valida jerarquía, unicidad y
/// formatos aunque el cliente sea modificado.
class FirestoreStaffRepository implements StaffRepository {
  FirestoreStaffRepository(this._firestore, this._accounts);

  final FirebaseFirestore _firestore;
  final StaffAccountCreator _accounts;

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _firestore.collection(name);

  @override
  Stream<List<StaffMember>> watchAll() =>
      _col(FirestorePaths.usuarios).snapshots().map((s) => [
            for (final d in s.docs)
              ?StaffMember.fromMap(d.id, d.data()),
          ]);

  @override
  Future<bool> documentExists(String documento) async =>
      (await _col(FirestorePaths.documentos).doc(documento).get()).exists;

  @override
  Future<bool> emailExists(String email) async =>
      (await _col(FirestorePaths.correos).doc(email).get()).exists;

  @override
  Future<CreatedStaff> create(StaffDraft draft, {required AppUser actor}) async {
    final account = await _accounts.createAccount(draft.emailNormalizado);
    final uid = account.uid;
    final batch = _firestore.batch();
    final auditId = addAuditEntry(
      _firestore,
      batch,
      actor: actor,
      accion: AuditAction.crearTrabajador,
      objetivo: uid,
    );
    batch.set(_col(FirestorePaths.usuarios).doc(uid), {
      'email': draft.emailNormalizado,
      'nombre': '${draft.nombres.trim()} ${draft.apellidos.trim()}',
      'nombres': draft.nombres.trim(),
      'apellidos': draft.apellidos.trim(),
      'tipoDocumento': draft.documentType.value,
      'numeroDocumento': draft.documentoNormalizado,
      'celular': draft.celular.trim(),
      if (draft.alternoNormalizado != null)
        'celularAlterno': draft.alternoNormalizado,
      'rol': draft.role.value,
      'estado': StaffStatus.activo.value,
      'activo': true,
      'fechaIngreso': StaffMember.formatDate(draft.fechaIngreso),
      'creadoEn': FieldValue.serverTimestamp(),
      'creadoPor': actor.uid,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    batch.set(_col(FirestorePaths.documentos).doc(draft.documentoNormalizado),
        {'uid': uid, 'creadoEn': FieldValue.serverTimestamp()});
    batch.set(_col(FirestorePaths.correos).doc(draft.emailNormalizado),
        {'uid': uid, 'creadoEn': FieldValue.serverTimestamp()});
    try {
      await batch.commit();
    } catch (_) {
      // Sin ficha no debe quedar una cuenta de acceso huérfana.
      await account.rollback();
      rethrow;
    }
    final mail = await account.commit();
    return CreatedStaff(uid,
        resetEmailSent: mail.passwordResetSent,
        verificationSent: mail.verificationSent);
  }

  @override
  Future<void> update(
    StaffMember current,
    StaffDraft draft, {
    required AppUser actor,
  }) {
    final changes = <String, Object?>{
      'nombres': draft.nombres.trim(),
      'apellidos': draft.apellidos.trim(),
      'nombre': '${draft.nombres.trim()} ${draft.apellidos.trim()}',
      'celular': draft.celular.trim(),
      'celularAlterno': draft.alternoNormalizado ?? FieldValue.delete(),
      'rol': draft.role.value,
      'fechaIngreso': StaffMember.formatDate(draft.fechaIngreso),
    };
    final changed = <String>[
      if (current.nombres != draft.nombres.trim()) 'nombres',
      if (current.apellidos != draft.apellidos.trim()) 'apellidos',
      if (current.celular != draft.celular.trim()) 'celular',
      if (current.celularAlterno != draft.alternoNormalizado) 'celularAlterno',
      if (current.role != draft.role) 'rol',
      if (StaffMember.formatDate(current.fechaIngreso) !=
          StaffMember.formatDate(draft.fechaIngreso))
        'fechaIngreso',
    ];
    return _commitUserChange(
        current.uid, actor, AuditAction.editarTrabajador, changed, changes);
  }

  @override
  Future<void> changeStatus(
    StaffMember target,
    StatusChange change, {
    required AppUser actor,
  }) async {
    final batch = _firestore.batch();
    final movement = _col(FirestorePaths.movimientos).doc();
    batch.set(movement, {
      'uid': target.uid,
      'tipo': change.isReactivation ? 'reactivacion' : change.reason!.value,
      'estadoNuevo': change.newStatus.value,
      'motivo': change.detail.trim(),
      'actorUid': actor.uid,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    final auditId = addAuditEntry(
      _firestore,
      batch,
      actor: actor,
      accion: AuditAction.cambiarEstado,
      objetivo: target.uid,
      campos: ['estado'],
    );
    batch.update(_col(FirestorePaths.usuarios).doc(target.uid), {
      'estado': change.newStatus.value,
      'activo': change.newStatus.canAccess,
      'bajaTipo': change.reason?.value ?? FieldValue.delete(),
      'ultimoMovimientoId': movement.id,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    await batch.commit();
  }

  @override
  Future<void> setRegularizationPermission(
    StaffMember target, {
    required bool allowed,
    required AppUser actor,
  }) =>
      _commitUserChange(target.uid, actor, AuditAction.autorizarRegularizar,
          ['puedeRegularizar'], {'puedeRegularizar': allowed});

  @override
  Future<void> assignSchedule(
    StaffMember target,
    String? scheduleId, {
    required AppUser actor,
  }) =>
      _commitUserChange(target.uid, actor, AuditAction.editarTrabajador,
          ['horarioId'], {'horarioId': scheduleId ?? FieldValue.delete()});

  Future<void> _commitUserChange(
    String uid,
    AppUser actor,
    String action,
    List<String> changedFields,
    Map<String, Object?> changes,
  ) async {
    final batch = _firestore.batch();
    final auditId = addAuditEntry(_firestore, batch,
        actor: actor, accion: action, objetivo: uid, campos: changedFields);
    batch.update(_col(FirestorePaths.usuarios).doc(uid), {
      ...changes,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'ultimaAuditoriaId': auditId,
    });
    await batch.commit();
  }
}
