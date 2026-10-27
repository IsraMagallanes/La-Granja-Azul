import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granja_azul/features/auth/repositories/auth_repository.dart';
import 'package:granja_azul/features/auth/repositories/firebase_auth_repository.dart';

/// Usuario de Firebase simulado: `reload()` cambia `emailVerified` sin hacer
/// emitir a `userChanges`, como ocurre en algunos dispositivos Android.
class _FakeUser implements User {
  _FakeUser({this.verifiedAfterReload = true});

  final bool verifiedAfterReload;
  final calls = <String>[];
  bool _verified = false;

  @override
  String get uid => 'u1';
  @override
  String? get email => 'sa@gmail.com';
  @override
  bool get emailVerified => _verified;

  @override
  Future<void> reload() async {
    calls.add('reload');
    _verified = verifiedAfterReload;
  }

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async {
    calls.add('getIdToken($forceRefresh)');
    return 'token';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth(this.user);

  final _FakeUser user;
  final changes = StreamController<User?>.broadcast();

  @override
  User? get currentUser => user;

  /// Como el real: entrega el usuario actual al suscribirse.
  @override
  Stream<User?> userChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FirebaseAuthRepository.reloadAccount («Ya verifiqué»)', () {
    test('recarga, refresca el token y publica la cuenta verificada aunque userChanges no emita', () async {
      final user = _FakeUser();
      final repo = FirebaseAuthRepository(_FakeFirebaseAuth(user));
      final seen = <AuthAccount?>[];
      final sub = repo.authStateChanges().listen(seen.add);
      await pumpEventQueue();
      expect(seen.last?.emailVerified, isFalse);

      await repo.reloadAccount();
      await pumpEventQueue();

      expect(user.calls, ['reload', 'getIdToken(true)']);
      expect(seen.last, const AuthAccount(uid: 'u1', email: 'sa@gmail.com', emailVerified: true));
      await sub.cancel();
    });

    test('si aún no verificó, no cambia el estado (sin falsos positivos)', () async {
      final user = _FakeUser(verifiedAfterReload: false);
      final repo = FirebaseAuthRepository(_FakeFirebaseAuth(user));
      final seen = <AuthAccount?>[];
      final sub = repo.authStateChanges().distinct().listen(seen.add);
      await pumpEventQueue();

      await repo.reloadAccount();
      await pumpEventQueue();

      expect(seen, hasLength(1));
      expect(seen.single?.emailVerified, isFalse);
      await sub.cancel();
    });

    test('sin sesión no hace nada', () async {
      final auth = _NoUserAuth();
      await FirebaseAuthRepository(auth).reloadAccount();
    });
  });
}

class _NoUserAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
