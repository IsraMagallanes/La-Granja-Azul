import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/user_repository.dart';

/// Se sobrescribe en `main.dart` con la implementación de Firebase.
final userRepositoryProvider = Provider<UserRepository>(
  (ref) => throw UnimplementedError('userRepositoryProvider sin override'),
);
