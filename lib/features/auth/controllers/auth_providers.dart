import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../users/controllers/user_providers.dart';
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
  return auth.authStateChanges().switchMap(
        (uid) => uid == null
            ? Stream<SessionState>.value(const Unauthenticated())
            : users.watchUser(uid).map(SessionResolver.fromProfile),
      );
});
