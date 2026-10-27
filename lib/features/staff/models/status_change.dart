import 'staff_status.dart';

/// Solicitud de cambio de estado laboral. El motivo escrito es obligatorio y
/// confidencial (solo lo lee el Superadmin).
class StatusChange {
  const StatusChange({
    required this.newStatus,
    required this.detail,
    this.reason,
  });

  final StaffStatus newStatus;

  /// Obligatorio al suspender o dar de baja; `null` al reactivar.
  final LeaveReason? reason;
  final String detail;

  bool get isReactivation => newStatus == StaffStatus.activo;
}
