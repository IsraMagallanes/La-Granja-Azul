import '../models/audit_entry.dart';

abstract interface class AuditRepository {
  /// Últimas acciones (solo Superadmin puede leerlas).
  Stream<List<AuditEntry>> watchRecent({int limit = 100});
}
