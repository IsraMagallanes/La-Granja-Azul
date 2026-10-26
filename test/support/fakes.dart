import 'dart:async';

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

  @override
  Stream<AppUser?> watchUser(String uid) => Stream.value(users[uid]);
}

/// Autenticación en memoria: contraseña válida `secreta1`.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({String? initialUid}) : _uid = initialUid;

  String? _uid;
  final _controller = StreamController<String?>.broadcast();
  final resets = <String>[];
  final Map<String, String> uidByEmail = {};

  @override
  Stream<String?> authStateChanges() async* {
    yield _uid;
    yield* _controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final uid = uidByEmail[email];
    if (uid == null || password != 'secreta1') {
      throw const AppFailure('Correo o contraseña incorrectos.');
    }
    _uid = uid;
    _controller.add(uid);
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);
}
