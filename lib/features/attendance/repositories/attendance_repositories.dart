import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';

/// App del personal: consulta su propia asistencia y pide correcciones.
abstract interface class WorkerAttendanceRepository {
  Stream<AttendanceState?> watchState(String uid);
  Stream<List<AttendanceRecord>> watchHistory(String uid, {int limit = 30});
  Stream<List<CorrectionRequest>> watchCorrections(String uid);

  Future<void> requestCorrection({
    required String uid,
    required String fecha,
    required String tipo,
    required String motivo,
  });
}

/// Generador del QR (Superadmin, Admin, Cajero). Generarlo NO registra
/// asistencia de nadie.
abstract interface class QrGenerationRepository {
  /// Crea un token vigente [QrToken.lifetime] a nombre de [generator].
  Future<QrToken> createToken(AppUser generator, String tokenId);
}

/// Escáner del QR (Mesero, Cocina, Cajero): registra SU entrada o salida.
abstract interface class QrScanRepository {
  Future<QrToken?> fetchToken(String tokenId);
  Future<AttendanceState?> fetchState(String uid);

  /// Registra de forma atómica la entrada o salida de [uid] con la hora del
  /// servidor y la devuelve. Lanza si las reglas del servidor lo rechazan.
  Future<DateTime> commit({
    required QrToken token,
    required String uid,
    required PunchType type,
    required AttendanceState? state,
  });
}

abstract interface class AttendanceAdminRepository {
  Stream<List<AttendanceRecord>> watchRange(DateTime from, DateTime to);
  Stream<List<Schedule>> watchSchedules();

  Future<void> saveSchedule(AppUser actor, Schedule schedule);

  /// Crea un registro manual (regularizado o supervisado). Si queda abierto
  /// actualiza también el estado de jornada.
  Future<void> regularizeCreate(
    AppUser actor, {
    required String uid,
    required DateTime entrada,
    required DateTime? salida,
    required AttendanceOrigin origin,
    required String motivo,
  });

  /// Corrige un registro existente. [closesOpenState] cierra la jornada
  /// abierta del trabajador al añadir la salida.
  Future<void> regularizeUpdate(
    AppUser actor, {
    required AttendanceRecord record,
    required DateTime entrada,
    required DateTime? salida,
    required String motivo,
    required bool closesOpenState,
  });

  Stream<List<CorrectionRequest>> watchAllCorrections();

  Future<void> resolveCorrection(
    AppUser actor,
    CorrectionRequest request, {
    required bool approved,
    required String respuesta,
  });
}

