import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  /// Empuja la cuenta ya recargada: `reload()` no siempre hace emitir a
  /// `userChanges`, así que «Ya verifiqué» no depende de ese evento.
  final _refreshed = PublishSubject<AuthAccount?>();

  static AuthAccount? _toAccount(User? user) => user == null
      ? null
      : AuthAccount(
          uid: user.uid,
          email: user.email ?? '',
          emailVerified: user.emailVerified,
        );

  // `userChanges` (no `authStateChanges`) para enterarse también de la
  // verificación del correo y de los cambios de token.
  @override
  Stream<AuthAccount?> authStateChanges() =>
      Rx.merge([_auth.userChanges().map(_toAccount), _refreshed]);

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      // El primer intento tras instalar la app o cambiar de red puede fallar
      // por un corte transitorio: se reintenta una vez antes de informar.
      if (e.code != 'network-request-failed') rethrow;
      await Future<void>.delayed(const Duration(seconds: 1));
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // No revelar si un correo está registrado.
      if (e.code != 'user-not-found') rethrow;
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.sendEmailVerification();
  }

  @override
  Future<void> reloadAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    // El token nuevo lleva `email_verified: true`, que exigen las reglas.
    await _auth.currentUser?.getIdToken(true);
    _refreshed.add(_toAccount(_auth.currentUser));
  }
}
