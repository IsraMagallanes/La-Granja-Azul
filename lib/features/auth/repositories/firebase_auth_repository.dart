import 'package:firebase_auth/firebase_auth.dart';

import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((user) => user?.uid);

  @override
  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

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
}
