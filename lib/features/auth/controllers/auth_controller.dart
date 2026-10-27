import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import 'auth_providers.dart';

/// Ejecuta acciones de autenticación y expone su estado de carga/error.
class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> signIn(String email, String password) => _run(
        () => ref
            .read(authRepositoryProvider)
            .signIn(email: email.trim(), password: password),
      );

  /// Pide el enlace de contraseña con tiempo máximo y sin duplicar solicitudes.
  /// `true` solo si Firebase aceptó la solicitud.
  Future<bool> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    final outcome =
        await ref.read(emailRequesterProvider).sendPasswordReset(email);
    state = outcome.ok
        ? const AsyncData(null)
        : AsyncError(AppFailure(outcome.message), StackTrace.current);
    return outcome.ok;
  }

  Future<bool> signOut() => _run(ref.read(authRepositoryProvider).signOut);

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      // Diagnóstico: en depuración se registra la excepción real (tipo, código y
      // mensaje) para distinguir fallos de red de otros problemas.
      if (kDebugMode) debugPrint('Auth error: ${e.runtimeType} -> $e');
      state = AsyncError(ErrorMapper.map(e), st);
      return false;
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);
