import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/async/request_guard.dart';
import '../../attendance/controllers/attendance_providers.dart';
import '../../attendance/controllers/terminal_providers.dart';
import '../../attendance/repositories/attendance_repositories.dart';
import '../../roles/controllers/role_providers.dart';
import '../../roles/services/permission_service.dart';
import '../../users/controllers/user_providers.dart';
import '../../users/models/app_user.dart';
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
/// que desactivar a un usuario o cambiar su rol surte efecto en vivo. Para los
/// roles no exentos también sigue `estadoAsistencia/{uid}`: registrar entrada o
/// salida abre o cierra el acceso operativo al instante.
final sessionProvider = StreamProvider<SessionState>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final users = ref.watch(userRepositoryProvider);
  final terminals = ref.watch(terminalRepositoryProvider);
  final permissions = ref.watch(permissionServiceProvider);
  return auth.authStateChanges().distinct().switchMap(
    (account) => account == null
        ? Stream<SessionState>.value(const Unauthenticated())
        : _accountSession(
            users,
            terminals,
            permissions,
            () => ref.read(workerAttendanceRepositoryProvider),
            account,
          ),
  );
});

/// Sesión de una cuenta con sesión de Firebase: personal si tiene perfil; si
/// no, puede ser una terminal de asistencia autorizada.
///
/// Sigue el perfil y, según su rol, la jornada o la terminal. Cada cambio del
/// perfil reemplaza la suscripción interior; se gestiona a mano (y no con
/// `switchMap` anidado) para que la sesión nunca dependa de que termine un
/// stream interior ya completado.
Stream<SessionState> _accountSession(
  UserRepository users,
  TerminalRepository terminals,
  PermissionService permissions,
  WorkerAttendanceRepository Function() attendance,
  AuthAccount account,
) {
  final uid = account.uid;
  late final StreamController<SessionState> out;
  StreamSubscription<AppUser?>? profileSub;
  StreamSubscription<SessionState>? innerSub;
  var profileDone = false;
  var innerDone = true;

  // Como un `async*`: la sesión termina cuando terminan sus fuentes. Las de
  // Firestore no terminan nunca; las de prueba sí.
  void closeIfDone() {
    if (profileDone && innerDone && !out.isClosed) out.close();
  }

  Stream<SessionState> forProfile(AppUser? user) {
    if (user == null) {
      return terminals
          .watchTerminal(uid)
          .map((terminal) => SessionResolver.fromAccount(null, terminal));
    }
    SessionState resolve({required bool onShift}) =>
        SessionResolver.fromProfile(
          user,
          emailVerified: account.emailVerified,
          onShift: onShift,
        );
    // Superadmin/Admin (y perfiles sin acceso) no dependen de la asistencia.
    if (!user.activo || permissions.isShiftExempt(user.role)) {
      return Stream.value(resolve(onShift: true));
    }
    // Sin dato o con error, la jornada se considera cerrada.
    return attendance()
        .watchState(uid)
        .map((state) => resolve(onShift: state?.abierta == true))
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (_, _, sink) => sink.add(resolve(onShift: false)),
          ),
        );
  }

  out = StreamController<SessionState>(
    onListen: () {
      profileSub = users
          .watchUser(uid)
          .listen(
            (user) {
              innerSub?.cancel();
              innerDone = false;
              innerSub = forProfile(user).listen(
                out.add,
                onError: out.addError,
                onDone: () {
                  innerDone = true;
                  closeIfDone();
                },
              );
            },
            onError: out.addError,
            onDone: () {
              profileDone = true;
              closeIfDone();
            },
          );
    },
    // Sin `await`: cancelar una suscripción ya completada no debe retener al
    // `switchMap` exterior que cambia de cuenta.
    onCancel: () {
      innerSub?.cancel();
      profileSub?.cancel();
    },
  );
  return out.stream;
}

/// Un solo guardián para toda la app: así dos pantallas no piden el mismo
/// correo a la vez.
final requestGuardProvider = Provider<RequestGuard>((ref) => RequestGuard());

final emailRequesterProvider = Provider<EmailRequester>(
  (ref) => EmailRequester(
    ref.watch(authRepositoryProvider),
    ref.watch(requestGuardProvider),
  ),
);

/// Marca la activación del trabajador al primer acceso con correo verificado.
final activationTrackerProvider = Provider<ActivationTracker>(
  (ref) => ActivationTracker(ref.watch(userRepositoryProvider)),
);
