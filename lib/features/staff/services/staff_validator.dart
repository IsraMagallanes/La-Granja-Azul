import '../../../core/validators/validators.dart';
import '../models/staff_draft.dart';

/// Validación de un [StaffDraft]. Devuelve `campo → mensaje`; vacío si es
/// válido.
class StaffValidator {
  const StaffValidator();

  Map<String, String> validate(StaffDraft draft, {DateTime? today}) {
    final errors = <String, String>{};
    void check(String field, String? message) {
      if (message != null) errors[field] = message;
    }

    check('nombres', Validators.persona(draft.nombres, field: 'Los nombres'));
    check('apellidos',
        Validators.persona(draft.apellidos, field: 'Los apellidos'));
    check('documento', draft.documentType.validate(draft.documento));
    check('email', Validators.email(draft.email));
    check('celular', Validators.celular(draft.celular));
    check('celularAlterno', Validators.celularOpcional(draft.celularAlterno));
    if (draft.alternoNormalizado != null &&
        draft.alternoNormalizado == draft.celular.trim()) {
      errors['celularAlterno'] =
          'El celular alternativo debe ser distinto al principal.';
    }

    final now = today ?? DateTime.now();
    final limit = DateTime(now.year, now.month, now.day + 1);
    if (!draft.fechaIngreso.isBefore(limit)) {
      errors['fechaIngreso'] = 'La fecha de ingreso no puede ser futura.';
    }
    return errors;
  }
}
