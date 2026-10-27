import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';

/// App del trabajador: genera su QR y consulta su propia asistencia.
abstract interface class WorkerAttendanceRepository {
  /// Crea un token de un solo uso (vigencia [QrToken.lifetime]). No registra
  /// asistencia: solo la terminal autorizada puede hacerlo.
  Future<QrToken> createToken(AppUser worker, PunchType type, String tokenId);

  Stream<QrToken?> watchToken(String tokenId);
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

/// Terminal del restaurante: consume el QR contra el servidor.
abstract interface class TerminalScanRepository {
  Future<QrToken?> fetchToken(String tokenId);
  Future<AttendanceState?> fetchState(String uid);

  /// Registra (una sola vez) el secreto que enlaza esta cuenta de terminal
  /// con el dispositivo. Falla si ya existe uno.
  Future<void> enroll({required String terminalUid, required String key});

  /// Registra la entrada o salida de forma atómica con la hora del servidor y
  /// devuelve esa hora. Lanza si las reglas del servidor lo rechazan.
  Future<DateTime> commit({
    required QrToken token,
    required AttendanceState? state,
    required String terminalUid,
    required String deviceKey,
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

/// Alta, consulta y revocación de terminales (solo Superadmin).
abstract interface class TerminalRepository {
  /// Perfil de terminal del usuario autenticado, si lo es.
  Stream<AttendanceTerminal?> watchTerminal(String uid);
  Stream<List<AttendanceTerminal>> watchAll();

  Future<void> authorize(AppUser actor, {required String nombre, required String uid});
  Future<void> setActive(AppUser actor, AttendanceTerminal terminal,
      {required bool active});

  /// Borra el secreto del dispositivo: la terminal podrá enlazarse de nuevo
  /// (p. ej. tablet reemplazada o credenciales comprometidas).
  Future<void> resetDeviceLink(AppUser actor, AttendanceTerminal terminal);
}

