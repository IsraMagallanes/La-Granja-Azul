import 'dart:math';

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/validators/validators.dart';
import '../../roles/models/user_role.dart';
import '../../staff/repositories/staff_repository.dart';
import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import '../repositories/attendance_repositories.dart';
import 'qr_payload.dart';
import 'regularization.dart';
import 'scan_validator.dart';
import 'terminal_binding.dart';

/// QR emitido para el trabajador. Generarlo NO registra asistencia.
class IssuedQr {
  const IssuedQr({required this.payload, required this.token, required this.expiresAt});

  /// Texto que se dibuja en el QR.
  final String payload;
  final QrToken token;

  /// Fin de la cuenta regresiva en el reloj local (informativo: la vigencia
  /// real la decide el servidor).
  final DateTime expiresAt;
}

/// App del trabajador.
class QrIssueService {
  const QrIssueService(this._repo, {this._random});

  final WorkerAttendanceRepository _repo;
  final Random? _random;

  Future<IssuedQr> issue(
    AppUser worker,
    PunchType type, {
    required AttendanceState? state,
    DateTime Function() clock = DateTime.now,
  }) async {
    final open = state?.abierta ?? false;
    if (type == PunchType.entrada && open) {
      throw const AppFailure('Ya tienes una entrada abierta. Genera el QR de salida.');
    }
    if (type == PunchType.salida && !open) {
      throw const AppFailure('No tienes una entrada abierta para registrar salida.');
    }
    if (!worker.activo) {
      throw const AppFailure('Tu cuenta no está activa.');
    }
    final id = QrPayload.generateId(_random);
    final token = await _repo.createToken(worker, type, id);
    return IssuedQr(
      payload: QrPayload.encode(token.id),
      token: token,
      expiresAt: clock().add(QrToken.lifetime),
    );
  }

  Future<void> requestCorrection({
    required AppUser worker,
    required String fecha,
    required String tipo,
    required String motivo,
  }) async {
    if (DateTime.tryParse(fecha) == null) {
      throw const AppFailure('Fecha inválida.');
    }
    final error = Validators.motivo(motivo);
    if (error != null) throw AppFailure(error);
    await _repo.requestCorrection(
        uid: worker.uid, fecha: fecha, tipo: tipo, motivo: motivo);
  }
}

class ScanResult {
  const ScanResult.ok({
    required this.type,
    required this.name,
    required this.at,
  })  : success = true,
        message = '';

  const ScanResult.failed(this.message)
      : success = false,
        type = null,
        name = '',
        at = null;

  final bool success;
  final String message;
  final PunchType? type;
  final String name;

  /// Hora del servidor.
  final DateTime? at;
}

/// Terminal del restaurante: lee el QR, identifica entrada o salida y registra
/// solo después de que el servidor lo valida.
class TerminalScanService {
  const TerminalScanService(
    this._repo,
    this._keys, {
    this._validator = const ScanValidator(),
  });

  final TerminalScanRepository _repo;
  final DeviceKeyStore _keys;
  final ScanValidator _validator;

  Future<ScanResult> process(String? raw, {required String terminalUid}) async {
    final tokenId = QrPayload.decode(raw);
    if (tokenId == null) return const ScanResult.failed('QR no válido.');
    final deviceKey = await _keys.read(terminalUid);
    if (deviceKey == null) {
      return const ScanResult.failed(
          'Esta tablet no está enlazada a la terminal. Inicia sesión de nuevo.');
    }
    try {
      final token = await _repo.fetchToken(tokenId);
      final state = token == null ? null : await _repo.fetchState(token.uid);
      final decision = _validator.evaluate(token: token, state: state);
      if (decision is ScanRejected) return ScanResult.failed(decision.message);
      final ok = decision as ScanProceed;
      final at = await _repo.commit(
        token: ok.token,
        state: state,
        terminalUid: terminalUid,
        deviceKey: deviceKey,
      );
      return ScanResult.ok(
        type: ok.token.tipo,
        name: ok.token.nombreMostrar,
        at: at,
      );
    } catch (e) {
      return ScanResult.failed(await _explain(e, tokenId));
    }
  }

  /// El servidor rechazó la escritura (o falló la red). Intenta dar el motivo
  /// más claro: QR ya usado, vencido, trabajador inactivo, etc.
  Future<String> _explain(Object error, String tokenId) async {
    final mapped = ErrorMapper.map(error);
    if (mapped.code != 'permission-denied') return mapped.message;
    try {
      final token = await _repo.fetchToken(tokenId);
      if (token == null) return 'QR no válido.';
      if (token.used) return 'Este QR ya fue utilizado.';
    } catch (_) {
      // Sin detalle adicional.
    }
    return 'El servidor rechazó el QR: venció (45 s), no es válido o el '
        'trabajador no está activo.';
  }
}

/// Administración de terminales (solo Superadmin).
class TerminalAdminService {
  const TerminalAdminService(this._repo, this._accounts);

  final TerminalRepository _repo;
  final StaffAccountCreator _accounts;

  Future<void> register(
    AppUser actor, {
    required String nombre,
    required String email,
    required String password,
  }) async {
    _ensureSuper(actor);
    if (nombre.trim().length < 2) throw const AppFailure('Indica el nombre de la terminal.');
    final mail = Validators.email(email);
    if (mail != null) throw AppFailure(mail);
    if (password.length < 10) {
      throw const AppFailure('La contraseña de la terminal debe tener al menos 10 caracteres.');
    }
    final account = await _accounts.createAccount(email.trim().toLowerCase(),
        password: password);
    try {
      await _repo.authorize(actor, nombre: nombre, uid: account.uid);
    } catch (_) {
      await account.rollback();
      rethrow;
    }
    await account.commit();
  }

  Future<void> setActive(AppUser actor, AttendanceTerminal terminal,
      {required bool active}) async {
    _ensureSuper(actor);
    await _repo.setActive(actor, terminal, active: active);
  }

  Future<void> resetDeviceLink(AppUser actor, AttendanceTerminal terminal) async {
    _ensureSuper(actor);
    await _repo.resetDeviceLink(actor, terminal);
  }

  void _ensureSuper(AppUser actor) {
    if (actor.role != UserRole.superadmin) {
      throw const AppFailure('Solo el Superadmin administra terminales.');
    }
  }
}

/// Horarios y regularización (admin / superadmin).
class AttendanceAdminService {
  const AttendanceAdminService(
    this._repo, {
    this._regularization = const Regularization(),
  });

  final AttendanceAdminRepository _repo;
  final Regularization _regularization;

  Future<void> saveSchedule(
    AppUser actor, {
    String id = '',
    required String nombre,
    required String horaInicio,
    required String horaFin,
    required int toleranciaMin,
    required List<int> dias,
    bool activo = true,
  }) async {
    if (actor.role != UserRole.superadmin && actor.role != UserRole.admin) {
      throw const AppFailure('No tienes permiso para configurar horarios.');
    }
    final error = Schedule.validate(
      nombre: nombre,
      horaInicio: horaInicio,
      horaFin: horaFin,
      toleranciaMin: toleranciaMin,
      dias: dias,
    );
    if (error != null) throw AppFailure(error);
    await _repo.saveSchedule(
      actor,
      Schedule(
        id: id,
        nombre: nombre.trim(),
        inicioMin: Schedule.parseMinutes(horaInicio)!,
        finMin: Schedule.parseMinutes(horaFin)!,
        toleranciaMin: toleranciaMin,
        dias: (List.of(dias)..sort()),
        activo: activo,
      ),
    );
  }

  /// Registro manual (olvido de marcación o trabajador sin celular, con un
  /// responsable presente). Motivo obligatorio y auditoría.
  Future<void> regularizeNew(
    AppUser actor, {
    required String targetUid,
    required UserRole targetRole,
    required DateTime entrada,
    required DateTime? salida,
    required String motivo,
    required bool supervised,
    DateTime Function() clock = DateTime.now,
  }) async {
    _regularization.validate(
      actor: actor,
      targetRole: targetRole,
      targetUid: targetUid,
      entrada: entrada,
      salida: salida,
      motivo: motivo,
      now: clock(),
    );
    await _repo.regularizeCreate(
      actor,
      uid: targetUid,
      entrada: entrada,
      salida: salida,
      origin: _regularization.originFor(supervised: supervised),
      motivo: motivo,
    );
  }

  Future<void> regularizeExisting(
    AppUser actor, {
    required AttendanceRecord record,
    required UserRole targetRole,
    required DateTime entrada,
    required DateTime? salida,
    required String motivo,
    DateTime Function() clock = DateTime.now,
  }) async {
    _regularization.validate(
      actor: actor,
      targetRole: targetRole,
      targetUid: record.uid,
      entrada: entrada,
      salida: salida,
      motivo: motivo,
      now: clock(),
    );
    await _repo.regularizeUpdate(
      actor,
      record: record,
      entrada: entrada,
      salida: salida,
      motivo: motivo,
      closesOpenState: record.abierta && salida != null,
    );
  }

  Future<void> resolveCorrection(
    AppUser actor,
    CorrectionRequest request, {
    required bool approved,
    required String respuesta,
  }) async {
    if (!_regularization.canRegularize(actor)) {
      throw const AppFailure('No estás autorizado a resolver correcciones.');
    }
    if (respuesta.trim().length < 5) {
      throw const AppFailure('Escribe una respuesta para el trabajador.');
    }
    await _repo.resolveCorrection(actor, request,
        approved: approved, respuesta: respuesta);
  }
}
