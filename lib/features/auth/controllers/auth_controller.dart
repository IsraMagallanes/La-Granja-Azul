import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<bool> sendPasswordReset(String email) => _run(
        () => ref.read(authRepositoryProvider).sendPasswordReset(email.trim()),
      );

  Future<bool> signOut() => _run(ref.read(authRepositoryProvider).signOut);

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(ErrorMapper.map(e), st);
      return false;
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);
