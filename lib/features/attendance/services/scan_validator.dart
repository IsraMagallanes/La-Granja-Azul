import '../models/attendance_models.dart';

/// Resultado de evaluar un QR escaneado antes de intentar registrarlo.
sealed class ScanDecision {
  const ScanDecision();
}

class ScanProceed extends ScanDecision {
  const ScanProceed(this.token, {this.openRecordId});

  final QrToken token;

  /// Registro abierto que cierra una salida.
  final String? openRecordId;
}

class ScanRejected extends ScanDecision {
  const ScanRejected(this.message);

  final String message;
}

/// Reglas de negocio de la terminal. Son un filtro previo para dar mensajes
/// claros; la validación definitiva y atómica la hacen `firestore.rules`
/// (token sin usar y vigente, terminal autorizada, trabajador activo, entrada
/// única y salida con entrada abierta).
class ScanValidator {
  const ScanValidator();

  ScanDecision evaluate({required QrToken? token, AttendanceState? state}) {
    if (token == null) return const ScanRejected('QR no válido.');
    if (token.used) return const ScanRejected('Este QR ya fue utilizado.');
    final open = state?.abierta ?? false;
    switch (token.tipo) {
      case PunchType.entrada:
        if (open) {
          return const ScanRejected(
              'Ya tiene una entrada registrada. Genere el QR de salida.');
        }
        return ScanProceed(token);
      case PunchType.salida:
        if (!open || state?.asistenciaId == null) {
          return const ScanRejected(
              'No hay una entrada abierta: no se puede registrar la salida.');
        }
        return ScanProceed(token, openRecordId: state!.asistenciaId);
    }
  }
}
