abstract interface class AuthRepository {
  /// UID del usuario autenticado o `null` si no hay sesión.
  Stream<String?> authStateChanges();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);
}
