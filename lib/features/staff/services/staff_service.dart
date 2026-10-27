import '../../../core/error/app_failure.dart';
import '../../roles/models/user_role.dart';
import '../../users/models/app_user.dart';
import '../models/rehire_restriction.dart';
import '../models/staff_draft.dart';
import '../models/staff_member.dart';
import '../models/staff_status.dart';
import '../models/status_change.dart';
import '../repositories/staff_repository.dart';
import 'staff_policy.dart';
import 'staff_validator.dart';

class CreateStaffResult {
  const CreateStaffResult(this.uid,
      {this.restriction, this.resetEmailSent = true, this.verificationSent = true});

  final String uid;

  /// `false` si el correo para definir la contraseña no pudo enviarse: hay que
  /// reenviarlo desde la ficha del trabajador.
  final bool resetEmailSent;

  /// `false` si el correo de verificación no pudo enviarse.
  final bool verificationSent;

  /// Restricción vigente del documento: solo informativa.
  final RehireRestriction? restriction;
}

/// Casos de uso de gestión de personal: valida, aplica la jerarquía y delega
/// la persistencia al repositorio.
class StaffService {
  const StaffService(
    this._staff,
    this._restrictions, {
    this._policy = const StaffPolicy(),
    this._validator = const StaffValidator(),
  });

  final StaffRepository _staff;
  final RestrictionRepository _restrictions;
  final StaffPolicy _policy;
  final StaffValidator _validator;

  Future<CreateStaffResult> create(AppUser actor, StaffDraft draft) async {
    if (!_policy.canAssign(actor.role, draft.role)) {
      throw const AppFailure('No puedes asignar ese rol.');
    }
    _ensureValid(draft);
    final documento = draft.documentoNormalizado;
    if (await _staff.documentExists(documento)) {
      throw const AppFailure(
          'Ya existe un trabajador (activo o dado de baja) con ese documento.');
    }
    if (await _staff.emailExists(draft.emailNormalizado)) {
      throw const AppFailure(
          'Ya existe un trabajador (activo o dado de baja) con ese correo.');
    }
    final restriction = await _restrictions.find(documento);
    final created = await _staff.create(draft, actor: actor);
    return CreateStaffResult(
      created.uid,
      resetEmailSent: created.resetEmailSent,
      verificationSent: created.verificationSent,
      restriction: (restriction?.activa ?? false) ? restriction : null,
    );
  }

  Future<void> update(
    AppUser actor,
    StaffMember current,
    StaffDraft draft,
  ) async {
    _ensureCanManage(actor, current);
    if (!_policy.canAssign(actor.role, draft.role)) {
      throw const AppFailure('No puedes asignar ese rol.');
    }
    _ensureValid(draft);
    await _staff.update(current, draft, actor: actor);
  }

  Future<void> changeStatus(
    AppUser actor,
    StaffMember target,
    StatusChange change,
  ) async {
    _ensureCanManage(actor, target);
    if (target.estado == change.newStatus) {
      throw const AppFailure('El trabajador ya está en ese estado.');
    }
    if (!change.isReactivation && change.reason == null) {
      throw const AppFailure('Selecciona el motivo de la baja o suspensión.');
    }
    if (change.newStatus == StaffStatus.suspendido &&
        change.reason == LeaveReason.renuncia) {
      throw const AppFailure('Una renuncia es una baja, no una suspensión.');
    }
    if (change.detail.trim().length < 10) {
      throw const AppFailure('Describe el motivo (mínimo 10 caracteres).');
    }
    await _staff.changeStatus(target, change, actor: actor);
  }

  Future<void> setRegularizationPermission(
    AppUser actor,
    StaffMember target, {
    required bool allowed,
  }) async {
    if (!_policy.canGrantRegularization(actor.role)) {
      throw const AppFailure('Solo el Superadmin puede autorizar.');
    }
    if (target.role != UserRole.admin) {
      throw const AppFailure('Solo se autoriza a administradores.');
    }
    await _staff.setRegularizationPermission(target,
        allowed: allowed, actor: actor);
  }

  Future<void> assignSchedule(
    AppUser actor,
    StaffMember target,
    String? scheduleId,
  ) async {
    _ensureCanManage(actor, target);
    await _staff.assignSchedule(target, scheduleId, actor: actor);
  }

  void _ensureValid(StaffDraft draft) {
    final errors = _validator.validate(draft);
    if (errors.isNotEmpty) throw AppFailure(errors.values.first);
  }

  void _ensureCanManage(AppUser actor, StaffMember target) {
    if (!_policy.canManage(
      actorRole: actor.role,
      actorUid: actor.uid,
      target: target,
    )) {
      throw const AppFailure('No tienes permiso sobre este trabajador.');
    }
  }
}
