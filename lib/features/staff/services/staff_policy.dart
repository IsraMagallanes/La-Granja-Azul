import '../../roles/models/user_role.dart';
import '../models/staff_member.dart';

/// Reglas de jerarquía para administrar personal. Evita el escalamiento de
/// privilegios; `firestore.rules` aplica las mismas reglas en el servidor.
class StaffPolicy {
  const StaffPolicy();

  static const operationalRoles = {
    UserRole.mesero,
    UserRole.cocina,
    UserRole.cajero,
    UserRole.almacen,
  };

  /// Roles que [actor] puede asignar al crear o editar. Nadie crea
  /// superadmins desde la app (solo `tools/create_superadmin.js`).
  Set<UserRole> assignableRoles(UserRole actor) => switch (actor) {
        UserRole.superadmin => {UserRole.admin, ...operationalRoles},
        UserRole.admin => operationalRoles,
        _ => const {},
      };

  bool canAssign(UserRole actor, UserRole role) =>
      assignableRoles(actor).contains(role);

  /// Si [actor] puede editar, suspender, dar de baja o reactivar a [target].
  /// Nadie se administra a sí mismo, y un Admin nunca toca a otro Admin.
  bool canManage({
    required UserRole actorRole,
    required String actorUid,
    required StaffMember target,
  }) =>
      target.uid != actorUid && canAssign(actorRole, target.role);

  /// Solo el Superadmin administra restricciones de recontratación.
  bool canManageRestrictions(UserRole actor) => actor == UserRole.superadmin;

  /// Solo el Superadmin autoriza a un Admin a regularizar marcaciones.
  bool canGrantRegularization(UserRole actor) => actor == UserRole.superadmin;
}
