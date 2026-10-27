import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/async/request_guard.dart';
import '../../attendance/controllers/terminal_providers.dart';
import '../../attendance/repositories/attendance_repositories.dart';
import '../../users/controllers/user_providers.dart';
import '../../users/repositories/user_repository.dart';
import '../services/activation_tracker.dart';
import '../services/email_requester.dart';
import '../models/session_state.dart';
import '../repositories/auth_repository.dart';
import '../services/session_resolver.dart';

/// Se sobrescribe en `main.dart` con la implementación de Firebase.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider sin override'),
);

/// Estado de sesión reactivo: combina Auth con el perfil en Firestore, de modo
/// que desactivar a un usuario o cambiar su rol surte efecto en vivo.
final sessionProvider = StreamProvider<SessionState>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final users = ref.watch(userRepositoryProvider);
  final terminals = ref.watch(terminalRepositoryProvider);
  return auth.authStateChanges().distinct().switchMap(
        (account) => account == null
            ? Stream<SessionState>.value(const Unauthenticated())
            : _accountSession(users, terminals, account),
      );
});

/// Sesión de una cuenta con sesión de Firebase: personal si tiene perfil; si
/// no, puede ser una terminal de asistencia autorizada.
Stream<SessionState> _accountSession(
  UserRepository users,
  TerminalRepository terminals,
  AuthAccount account,
) async* {
  final uid = account.uid;
  await for (final user in users.watchUser(uid)) {
    if (user != null) {
      yield SessionResolver.fromProfile(user,
          emailVerified: account.emailVerified);
    } else {
      yield* terminals
          .watchTerminal(uid)
          .map((terminal) => SessionResolver.fromAccount(null, terminal));
    }
  }
}

/// Un solo guardián para toda la app: así dos pantallas no piden el mismo
/// correo a la vez.
final requestGuardProvider = Provider<RequestGuard>((ref) => RequestGuard());

final emailRequesterProvider = Provider<EmailRequester>(
  (ref) => EmailRequester(
      ref.watch(authRepositoryProvider), ref.watch(requestGuardProvider)),
);

/// Marca la activación del trabajador al primer acceso con correo verificado.
final activationTrackerProvider = Provider<ActivationTracker>(
  (ref) => ActivationTracker(ref.watch(userRepositoryProvider)),
);
