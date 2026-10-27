import 'dart:async';

import '../error/app_failure.dart';
import '../error/error_mapper.dart';

/// Resultado de una solicitud protegida por [RequestGuard].
sealed class GuardOutcome {
  const GuardOutcome();
}

/// La operación terminó y el servidor la confirmó.
class GuardDone extends GuardOutcome {
  const GuardDone();
}

/// Ya hay una solicitud igual en curso: no se duplica.
class GuardBusy extends GuardOutcome {
  const GuardBusy();
}

/// Se completó hace poco: hay que esperar [left] antes de repetirla.
class GuardCoolingDown extends GuardOutcome {
  const GuardCoolingDown(this.left);
  final Duration left;
}

/// Falló o no respondió a tiempo. No se confirmó la operación.
class GuardFailed extends GuardOutcome {
  const GuardFailed(this.failure);
  final AppFailure failure;

  bool get timedOut => failure.code == RequestGuard.timeoutCode;
}

/// Ejecuta solicitudes de red con tres garantías: un tiempo máximo de espera,
/// una sola solicitud en curso por clave y una pausa tras un envío exitoso.
/// Tras un fallo o un tiempo agotado se puede reintentar de inmediato.
class RequestGuard {
  RequestGuard({
    this.timeout = const Duration(seconds: 20),
    this.cooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const timeoutCode = 'timeout';

  final Duration timeout;
  final Duration cooldown;
  final DateTime Function() _now;
  final _running = <String>{};
  final _blockedUntil = <String, DateTime>{};

  bool isRunning(String key) => _running.contains(key);

  Future<GuardOutcome> run(String key, Future<void> Function() action) async {
    if (_running.contains(key)) return const GuardBusy();
    final until = _blockedUntil[key];
    if (until != null) {
      final left = until.difference(_now());
      if (left > Duration.zero) return GuardCoolingDown(left);
    }
    _running.add(key);
    try {
      await action().timeout(timeout);
      _blockedUntil[key] = _now().add(cooldown);
      return const GuardDone();
    } on TimeoutException {
      return GuardFailed(AppFailure(
        'No se recibió respuesta a tiempo (${timeout.inSeconds} s). '
        'No se pudo confirmar la operación: revisa tu conexión e inténtalo de nuevo.',
        code: timeoutCode,
      ));
    } catch (e) {
      return GuardFailed(ErrorMapper.map(e));
    } finally {
      _running.remove(key);
    }
  }
}
