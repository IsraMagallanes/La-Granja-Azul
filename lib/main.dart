import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/auth/controllers/auth_providers.dart';
import 'features/auth/repositories/firebase_auth_repository.dart';
import 'features/users/controllers/user_providers.dart';
import 'features/users/repositories/firestore_user_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FirebaseAuthRepository(FirebaseAuth.instance),
        ),
        userRepositoryProvider.overrideWithValue(
          FirestoreUserRepository(FirebaseFirestore.instance),
        ),
      ],
      child: const GranjaAzulApp(),
    ),
  );
}
