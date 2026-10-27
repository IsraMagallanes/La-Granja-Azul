/// Cuenta de Firebase Authentication con sesión iniciada.
class AuthAccount {
  const AuthAccount({
    required this.uid,
    required this.emailVerified,
    this.email = '',
  });

  final String uid;
  final String email;

  /// El correo fue verificado (enlace de Firebase). Es requisito de acceso.
  final bool emailVerified;

  @override
  bool operator ==(Object other) =>
      other is AuthAccount &&
      other.uid == uid &&
      other.email == email &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode => Object.hash(uid, email, emailVerified);
}

abstract interface class AuthRepository {
  /// Cuenta autenticada o `null` si no hay sesión. Emite también cuando
  /// cambia la verificación del correo (tras `reloadAccount`).
  Stream<AuthAccount?> authStateChanges();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Reenvía el correo de verificación a la cuenta con sesión iniciada.
  Future<void> sendEmailVerification();

  /// Vuelve a leer la cuenta y renueva el token, para que la verificación del
  /// correo surta efecto también en las reglas de Firestore.
  Future<void> reloadAccount();
}
