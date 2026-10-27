/// Estado laboral. Solo `activo` permite ingresar a la aplicación.
enum StaffStatus {
  activo('activo', 'Activo'),
  suspendido('suspendido', 'Suspendido'),
  baja('baja', 'De baja');

  const StaffStatus(this.value, this.label);

  final String value;
  final String label;

  bool get canAccess => this == activo;

  static StaffStatus? tryParse(Object? raw) {
    for (final status in values) {
      if (status.value == raw) return status;
    }
    return null;
  }
}

/// Motivo obligatorio al suspender o dar de baja.
enum LeaveReason {
  renuncia('renuncia', 'Renuncia'),
  despido('despido', 'Despido'),
  suspension('suspension', 'Suspensión'),
  otro('otro', 'Otro');

  const LeaveReason(this.value, this.label);

  final String value;
  final String label;

  static LeaveReason? tryParse(Object? raw) {
    for (final reason in values) {
      if (reason.value == raw) return reason;
    }
    return null;
  }
}
