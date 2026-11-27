import 'dart:math';

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/validators/validators.dart';
import '../../roles/models/user_role.dart';
import '../../users/models/app_user.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import '../repositories/attendance_repositories.dart';
import 'qr_payload.dart';
import 'regularization.dart';
import 'scan_validator.dart';

/// QR mostrado por un generador. Generarlo NO registra asistencia de nadie.
class IssuedQr {
  const IssuedQr({
    required this.payload,
    required this.token,
    required this.expiresAt,
  });

  /// Texto que se dibuja en el QR.
  final String payload;
  final QrToken token;

  /// Fin de la cuenta regresiva en el reloj local (informativo: la vigencia
  /// real la decide el servidor).
  final DateTime expiresAt;
}

/// Generación del QR de asistencia: solo Superadmin, Admin y Cajero.
class QrGenerationService {
  const QrGenerationService(
    this._repo, {
    this._policy = const QrPolicy(),
    this._random,
  });

  final QrGenerationRepository _repo;
  final QrPolicy _policy;
  final Random? _random;

  Future<IssuedQr> issue(
    AppUser generator, {
    DateTime Function() clock = DateTime.now,
  }) async {
    if (!_policy.canGenerate(generator.role)) {
      throw const AppFailure('Tu rol no puede generar el QR de asistencia.');
    }
    if (!generator.activo) {
      throw const AppFailure('Tu cuenta no está activa.');
    }
    final id = QrPayload.generateId(_random);
    final token = await _repo.createToken(generator, id);
    return IssuedQr(
      payload: QrPayload.encode(token.id),
      token: token,
      expiresAt: clock().add(QrToken.lifetime),
    );
  }
}

/// Acciones del personal sobre su propia asistencia.
class AttendanceSelfService {
  const AttendanceSelfService(this._repo);

  final WorkerAttendanceRepository _repo;

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
      uid: worker.uid,
      fecha: fecha,
      tipo: tipo,
      motivo: motivo,
    );
  }
}

class ScanResult {
  const ScanResult.ok({
    required this.type,
    required this.generator,
    required this.at,
  }) : success = true,
       message = '';

  const ScanResult.failed(this.message)
    : success = false,
      type = null,
      generator = '',
      at = null;

  final bool success;
  final String message;
  final PunchType? type;

  /// Nombre de quien mostró el QR.
  final String generator;

  /// Hora del servidor.
  final DateTime? at;
}

/// Escaneo del QR por el personal: identifica entrada o salida según su
/// jornada y registra solo después de que el servidor lo valida.
class AttendanceScanService {
  const AttendanceScanService(
    this._repo, {
    this._validator = const ScanValidator(),
  });

  final QrScanRepository _repo;
  final ScanValidator _validator;

  Future<ScanResult> process(
    String? raw, {
    required AppUser scanner,
    DateTime Function() clock = DateTime.now,
  }) async {
    final tokenId = QrPayload.decode(raw);
    if (tokenId == null) return const ScanResult.failed('QR no válido.');
    if (!scanner.activo) {
      return const ScanResult.failed('Tu cuenta no está activa.');
    }
    try {
      final token = await _repo.fetchToken(tokenId);
      final state = await _repo.fetchState(scanner.uid);
      final decision = _validator.evaluate(
        token: token,
        scannerRole: scanner.role,
        scannerUid: scanner.uid,
        now: clock(),
        state: state,
      );
      if (decision is ScanRejected) return ScanResult.failed(decision.message);
      final ok = decision as ScanProceed;
      final at = await _repo.commit(
        token: ok.token,
        uid: scanner.uid,
        type: ok.type,
        state: state,
      );
      return ScanResult.ok(
        type: ok.type,
        generator: ok.token.nombreMostrar,
        at: at,
      );
    } catch (e) {
      return ScanResult.failed(await _explain(e, tokenId));
    }
  }

  /// El servidor rechazó la escritura (o falló la red). Da el motivo más claro.
  Future<String> _explain(Object error, String tokenId) async {
    final mapped = ErrorMapper.map(error);
    if (mapped.code != 'permission-denied') return mapped.message;
    try {
      if (await _repo.fetchToken(tokenId) == null) return 'QR no válido.';
    } catch (_) {
      // Sin detalle adicional.
    }
    return 'El servidor rechazó el QR: venció (45 s), no corresponde a tu rol '
        'o tu cuenta no está activa.';
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
    await _repo.resolveCorrection(
      actor,
      request,
      approved: approved,
      respuesta: respuesta,
    );
  }
}
