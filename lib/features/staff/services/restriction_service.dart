import '../../../core/error/app_failure.dart';
import '../../../core/validators/validators.dart';
import '../../users/models/app_user.dart';
import '../repositories/staff_repository.dart';
import 'staff_policy.dart';

/// Restricciones de recontratación. Solo el Superadmin las establece o levanta,
/// siempre con justificación y fecha de revisión. Nunca se aplican de forma
/// automática: son un aviso al contratar.
class RestrictionService {
  const RestrictionService(
    this._repo, {
    this._policy = const StaffPolicy(),
  });

  final RestrictionRepository _repo;
  final StaffPolicy _policy;

  static String? validateDocument(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    if (Validators.dni(value) == null) return null;
    if (Validators.carnetExtranjeria(value) == null) return null;
    return 'Ingresa un DNI (8 dígitos) o un carné de extranjería válido.';
  }

  Future<void> establish(
    AppUser actor, {
    required String documento,
    required String justification,
    required DateTime reviewOn,
    DateTime? today,
  }) async {
    _ensureSuperadmin(actor);
    final docError = validateDocument(documento);
    if (docError != null) throw AppFailure(docError);
    final reason = Validators.motivo(justification);
    if (reason != null) throw AppFailure(reason);
    final now = today ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    if (!reviewOn.isAfter(todayDate)) {
      throw const AppFailure('La fecha de revisión debe ser futura.');
    }
    await _repo.set(
      documento: documento.trim().toUpperCase(),
      justification: justification,
      reviewOn: reviewOn,
      actor: actor,
    );
  }

  Future<void> lift(
    AppUser actor, {
    required String documento,
    required String justification,
  }) async {
    _ensureSuperadmin(actor);
    final reason = Validators.motivo(justification);
    if (reason != null) throw AppFailure(reason);
    await _repo.lift(
      documento: documento,
      justification: justification,
      actor: actor,
    );
  }

  Future<String?> justificationOf(AppUser actor, String documento) async {
    _ensureSuperadmin(actor);
    return _repo.readJustification(documento);
  }

  void _ensureSuperadmin(AppUser actor) {
    if (!_policy.canManageRestrictions(actor.role)) {
      throw const AppFailure(
          'Solo el Superadmin gestiona restricciones de recontratación.');
    }
  }
}
