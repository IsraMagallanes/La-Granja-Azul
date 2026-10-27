import '../../users/models/app_user.dart';
import '../models/rehire_restriction.dart';
import '../models/staff_draft.dart';
import '../models/staff_member.dart';
import '../models/status_change.dart';

/// Resultado de un alta: el correo de contraseña se envía solo si la ficha
/// quedó guardada; si el envío falla se informa para reenviarlo.
class CreatedStaff {
  const CreatedStaff(this.uid,
      {this.resetEmailSent = true, this.verificationSent = true});

  final String uid;

  /// Enlace de Firebase para definir la contraseña.
  final bool resetEmailSent;

  /// Correo de verificación de la dirección.
  final bool verificationSent;
}

abstract interface class StaffRepository {
  Stream<List<StaffMember>> watchAll();

  /// Los índices de documento y correo incluyen a personal dado de baja.
  Future<bool> documentExists(String documento);
  Future<bool> emailExists(String email);

  /// Crea la cuenta de acceso y la ficha de forma consistente: si la ficha no
  /// se guarda, la cuenta recién creada se elimina (sin registros huérfanos).
  Future<CreatedStaff> create(StaffDraft draft, {required AppUser actor});

  /// Edita datos modificables (el documento y el correo no cambian).
  Future<void> update(
    StaffMember current,
    StaffDraft draft, {
    required AppUser actor,
  });

  Future<void> changeStatus(
    StaffMember target,
    StatusChange change, {
    required AppUser actor,
  });

  Future<void> setRegularizationPermission(
    StaffMember target, {
    required bool allowed,
    required AppUser actor,
  });

  Future<void> assignSchedule(
    StaffMember target,
    String? scheduleId, {
    required AppUser actor,
  });
}

abstract interface class RestrictionRepository {
  /// Cualquier admin puede consultar si un documento tiene restricción
  /// (aviso informativo), pero no su justificación.
  Future<RehireRestriction?> find(String documento);

  Stream<List<RehireRestriction>> watchAll();

  /// Solo Superadmin. Lee la justificación confidencial.
  Future<String?> readJustification(String documento);

  Future<void> set({
    required String documento,
    required String justification,
    required DateTime reviewOn,
    required AppUser actor,
  });

  Future<void> lift({
    required String documento,
    required String justification,
    required AppUser actor,
  });
}

/// Resultado del envío de los correos de activación.
class ActivationMail {
  const ActivationMail({this.passwordResetSent = true, this.verificationSent = true});

  final bool passwordResetSent;
  final bool verificationSent;
}

/// Cuenta de acceso recién creada, pendiente de que se guarde su ficha.
abstract interface class PendingAccount {
  String get uid;

  /// Deshace la creación (elimina la cuenta). Nunca lanza.
  Future<void> rollback();

  /// Confirma la cuenta. Si usa contraseña aleatoria envía los correos de
  /// activación (definir contraseña y verificar correo) y informa cuáles
  /// salieron; un fallo de envío no deshace la cuenta.
  Future<ActivationMail> commit();
}

/// Crea cuentas de acceso. Implementación de Firebase: instancia secundaria
/// de Auth. Sin [password] (personal) se usa una contraseña aleatoria que
/// nadie conoce y el trabajador define la suya con el correo de
/// restablecimiento. Con [password] (terminales) la fija quien autoriza el
/// dispositivo; no se guarda en ningún lado.
abstract interface class StaffAccountCreator {
  Future<PendingAccount> createAccount(String email, {String? password});
}
