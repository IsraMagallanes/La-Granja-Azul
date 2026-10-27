import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/attendance/controllers/attendance_providers.dart';
import 'features/attendance/controllers/terminal_providers.dart';
import 'features/attendance/repositories/firestore_attendance_repositories.dart';
import 'features/audit/repositories/firestore_audit.dart';
import 'features/auth/controllers/auth_providers.dart';
import 'features/auth/repositories/firebase_auth_repository.dart';
import 'features/staff/controllers/staff_providers.dart';
import 'features/staff/repositories/firebase_staff_account_creator.dart';
import 'features/staff/repositories/firestore_restriction_repository.dart';
import 'features/staff/repositories/firestore_staff_repository.dart';
import 'features/users/controllers/user_providers.dart';
import 'features/users/repositories/firestore_user_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final firestore = FirebaseFirestore.instance;
  final accounts = FirebaseStaffAccountCreator();

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FirebaseAuthRepository(FirebaseAuth.instance),
        ),
        userRepositoryProvider.overrideWithValue(
          FirestoreUserRepository(firestore),
        ),
        staffAccountCreatorProvider.overrideWithValue(accounts),
        staffRepositoryProvider.overrideWithValue(
          FirestoreStaffRepository(firestore, accounts),
        ),
        restrictionRepositoryProvider.overrideWithValue(
          FirestoreRestrictionRepository(firestore),
        ),
        auditRepositoryProvider.overrideWithValue(
          FirestoreAuditRepository(firestore),
        ),
        workerAttendanceRepositoryProvider.overrideWithValue(
          FirestoreWorkerAttendanceRepository(firestore),
        ),
        terminalScanRepositoryProvider.overrideWithValue(
          FirestoreTerminalScanRepository(firestore),
        ),
        attendanceAdminRepositoryProvider.overrideWithValue(
          FirestoreAttendanceAdminRepository(firestore),
        ),
        terminalRepositoryProvider.overrideWithValue(
          FirestoreTerminalRepository(firestore),
        ),
      ],
      child: const GranjaAzulApp(),
    ),
  );
}
