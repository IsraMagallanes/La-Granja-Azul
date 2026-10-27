import 'package:rxdart/rxdart.dart';

import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/auth/repositories/auth_repository.dart';
import 'package:granja_azul/features/roles/models/user_role.dart';
import 'package:granja_azul/features/users/models/app_user.dart';
import 'package:granja_azul/features/users/repositories/user_repository.dart';

AppUser buildUser({
  String uid = 'u1',
  UserRole role = UserRole.admin,
  bool activo = true,
}) =>
    AppUser(
      uid: uid,
      email: '$uid@granja.pe',
      nombre: 'Usuario $uid',
      role: role,
      activo: activo,
    );

class FakeUserRepository implements UserRepository {
  final Map<String, AppUser> users = {};

  final activated = <String>[];

  @override
  Stream<AppUser?> watchUser(String uid) => Stream.value(users[uid]);

  @override
  Future<void> markActivated(String uid) async => activated.add(uid);
}

/// Autenticación en memoria: contraseña válida `secreta1`.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({String? initialUid, bool verified = true})
      : _state = BehaviorSubject.seeded(
          initialUid == null
              ? null
              : AuthAccount(uid: initialUid, emailVerified: verified),
        );

  /// UIDs cuyo correo NO está verificado (por defecto todos lo están).
  final unverifiedUids = <String>{};
  int verificationsSent = 0;
  int reloads = 0;

  /// Reproduce el comportamiento de `authStateChanges`: entrega el valor actual
  /// y cada cambio posterior, sin perder eventos por temporización.
  final BehaviorSubject<AuthAccount?> _state;
  final resets = <String>[];
  final Map<String, String> uidByEmail = {};

  @override
  Stream<AuthAccount?> authStateChanges() => _state.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final uid = uidByEmail[email];
    if (uid == null || password != 'secreta1') {
      throw const AppFailure('Correo o contraseña incorrectos.');
    }
    _state.add(AuthAccount(uid: uid, emailVerified: !unverifiedUids.contains(uid)));
  }

  @override
  Future<void> signOut() async {
    _state.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);

  @override
  Future<void> sendEmailVerification() async => verificationsSent++;

  /// Simula pulsar «Ya verifiqué» tras abrir el enlace del correo.
  @override
  Future<void> reloadAccount() async {
    reloads++;
    final current = _state.valueOrNull;
    if (current != null) {
      unverifiedUids.remove(current.uid);
      _state.add(AuthAccount(uid: current.uid, emailVerified: true));
    }
  }
}
