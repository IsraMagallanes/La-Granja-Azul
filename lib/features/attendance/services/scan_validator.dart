import '../../roles/models/permission.dart';
import '../../roles/models/user_role.dart';
import '../../roles/services/permission_service.dart';
import '../models/attendance_models.dart';

/// Quién genera y quién escanea el QR de asistencia. Deriva de la matriz de
/// permisos (única fuente de verdad); `firestore.rules` aplica lo mismo.
class QrPolicy {
  const QrPolicy([this._permissions = const PermissionService()]);

  final PermissionService _permissions;

  /// Superadmin, Admin y Cajero muestran el QR.
  bool canGenerate(UserRole role) =>
      _permissions.can(role, Permission.generateAttendanceQr);

  /// Mesero, Cocina y Cajero escanean con la cámara.
  bool canScan(UserRole role) =>
      _permissions.can(role, Permission.scanAttendanceQr);

  /// ¿Puede [scanner] registrarse con un QR generado por [generator]? El
  /// Cajero solo con QR de Admin o Superadmin; Mesero y Cocina, con cualquier
  /// generador autorizado.
  bool canScanFrom(UserRole scanner, UserRole generator) {
    if (!canScan(scanner) || !canGenerate(generator)) return false;
    if (scanner == UserRole.cajero) {
      return generator == UserRole.admin || generator == UserRole.superadmin;
    }
    return true;
  }
}

/// Resultado de evaluar un QR escaneado antes de intentar registrarlo.
sealed class ScanDecision {
  const ScanDecision();
}

class ScanProceed extends ScanDecision {
  const ScanProceed(this.token, this.type);

  final QrToken token;

  /// Determinado por la jornada: sin entrada abierta es entrada; con ella, salida.
  final PunchType type;
}

class ScanRejected extends ScanDecision {
  const ScanRejected(this.message);

  final String message;
}

/// Reglas de negocio del escaneo. Son un filtro previo para dar mensajes
/// claros; la validación definitiva y atómica la hacen `firestore.rules`
/// (QR vigente, generador permitido, trabajador activo, entrada única y salida
/// con entrada abierta).
class ScanValidator {
  const ScanValidator([this._policy = const QrPolicy()]);

  final QrPolicy _policy;

  ScanDecision evaluate({
    required QrToken? token,
    required UserRole scannerRole,
    required String scannerUid,
    required DateTime now,
    AttendanceState? state,
  }) {
    if (!_policy.canScan(scannerRole)) {
      return const ScanRejected('Tu rol no registra asistencia con QR.');
    }
    if (token == null) return const ScanRejected('QR no válido.');
    if (token.isExpiredAt(now)) {
      return const ScanRejected('El QR venció. Pide que se muestre uno nuevo.');
    }
    if (token.generadorUid == scannerUid) {
      return const ScanRejected('No puedes escanear tu propio QR.');
    }
    if (!_policy.canScanFrom(scannerRole, token.generadorRol)) {
      return const ScanRejected(
        'Con tu rol solo puedes registrarte con un QR de Administración.',
      );
    }
    if (state?.tokenId == token.id) {
      return const ScanRejected(
        'Ya usaste este QR. Espera a que se muestre uno nuevo.',
      );
    }
    final open = state?.abierta ?? false;
    if (open && state?.asistenciaId == null) {
      return const ScanRejected('La jornada abierta no tiene registro.');
    }
    return ScanProceed(token, open ? PunchType.salida : PunchType.entrada);
  }
}
