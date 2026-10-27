import '../../../core/error/app_failure.dart';
import '../../roles/models/user_role.dart';
import '../../staff/services/staff_policy.dart';
import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';

/// Quién puede regularizar marcaciones y con qué datos.
class Regularization {
  const Regularization({this.policy = const StaffPolicy()});

  final StaffPolicy policy;

  /// Superadmin siempre; Admin solo si el Superadmin lo autorizó.
  bool canRegularize(AppUser actor) =>
      actor.role == UserRole.superadmin ||
      (actor.role == UserRole.admin && actor.puedeRegularizar);

  /// Lanza [AppFailure] con el primer problema encontrado.
  void validate({
    required AppUser actor,
    required UserRole targetRole,
    required String targetUid,
    required DateTime entrada,
    required DateTime? salida,
    required String motivo,
    required DateTime now,
  }) {
    if (!canRegularize(actor)) {
      throw const AppFailure('No estás autorizado a regularizar marcaciones.');
    }
    if (targetUid == actor.uid) {
      throw const AppFailure('No puedes regularizar tu propia asistencia.');
    }
    if (!policy.canAssign(actor.role, targetRole)) {
      throw const AppFailure('No tienes permiso sobre este trabajador.');
    }
    if (motivo.trim().length < 10) {
      throw const AppFailure('Describe el motivo (mínimo 10 caracteres).');
    }
    if (entrada.isAfter(now)) {
      throw const AppFailure('La entrada no puede ser futura.');
    }
    if (salida != null) {
      if (!salida.isAfter(entrada)) {
        throw const AppFailure('La salida debe ser posterior a la entrada.');
      }
      if (salida.isAfter(now)) {
        throw const AppFailure('La salida no puede ser futura.');
      }
    }
  }

  /// Origen del registro: `supervisada` para trabajadores sin celular que
  /// marcan con un responsable; `regularizada` para correcciones.
  AttendanceOrigin originFor({required bool supervised}) =>
      supervised ? AttendanceOrigin.supervisada : AttendanceOrigin.regularizada;
}
