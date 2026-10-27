import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'staff_repository.dart';

/// Crea cuentas con una instancia secundaria de Firebase Auth para no cerrar
/// la sesión de quien administra.
///
/// - Personal: contraseña inicial aleatoria de 32 caracteres (RNG
///   criptográfico) que nadie conoce ni se guarda; el trabajador define la suya
///   con el correo oficial de restablecimiento de Firebase, que se envía solo
///   cuando su ficha ya quedó guardada (`commit`).
/// - Si guardar la ficha falla, `rollback` elimina la cuenta recién creada.
class FirebaseStaffAccountCreator implements StaffAccountCreator {
  static const _appName = 'alta-personal';

  @override
  Future<PendingAccount> createAccount(String email, {String? password}) async {
    final app = await _secondaryApp();
    final auth = FirebaseAuth.instanceFor(app: app);
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password ?? _randomPassword(),
    );
    return _Pending(auth, credential.user!, email, sendReset: password == null);
  }

  Future<FirebaseApp> _secondaryApp() async {
    for (final app in Firebase.apps) {
      if (app.name == _appName) return app;
    }
    return Firebase.initializeApp(
      name: _appName,
      options: Firebase.app().options,
    );
  }

  static String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
}

class _Pending implements PendingAccount {
  _Pending(this._auth, this._user, this._email, {required this.sendReset});

  final FirebaseAuth _auth;
  final User _user;
  final String _email;
  final bool sendReset;

  @override
  String get uid => _user.uid;

  @override
  Future<void> rollback() async {
    try {
      await _user.delete();
    } catch (_) {
      // Si no se pudo eliminar, la cuenta queda sin perfil (acceso denegado).
    } finally {
      await _signOut();
    }
  }

  @override
  Future<ActivationMail> commit() async {
    var resetSent = true;
    var verificationSent = true;
    if (sendReset) {
      // Dos correos independientes y en paralelo: un fallo o una espera larga en
      // uno no impide el otro ni deja la pantalla sin respuesta. `true` significa
      // que Firebase aceptó la solicitud; si no respondió a tiempo se informa
      // como no confirmado y el administrador puede reintentar.
      final results = await Future.wait([
        _confirmed(() => _auth.sendPasswordResetEmail(email: _email)),
        _confirmed(() => _user.sendEmailVerification()),
      ]);
      resetSent = results[0];
      verificationSent = results[1];
    }
    await _signOut();
    return ActivationMail(
        passwordResetSent: resetSent, verificationSent: verificationSent);
  }

  static const _mailTimeout = Duration(seconds: 20);

  Future<bool> _confirmed(Future<void> Function() send) async {
    try {
      await send().timeout(_mailTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}
