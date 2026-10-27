import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../staff/repositories/staff_repository.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import '../repositories/attendance_repositories.dart';
import '../services/attendance_services.dart';
import '../services/terminal_binding.dart';
import 'terminal_providers.dart';

/// Se sobrescriben en `main.dart` con las implementaciones de Firebase.
final workerAttendanceRepositoryProvider = Provider<WorkerAttendanceRepository>(
  (ref) => throw UnimplementedError('workerAttendanceRepositoryProvider sin override'),
);

final terminalScanRepositoryProvider = Provider<TerminalScanRepository>(
  (ref) => throw UnimplementedError('terminalScanRepositoryProvider sin override'),
);

final attendanceAdminRepositoryProvider = Provider<AttendanceAdminRepository>(
  (ref) => throw UnimplementedError('attendanceAdminRepositoryProvider sin override'),
);

final staffAccountCreatorProvider = Provider<StaffAccountCreator>(
  (ref) => throw UnimplementedError('staffAccountCreatorProvider sin override'),
);

final qrIssueServiceProvider = Provider<QrIssueService>(
  (ref) => QrIssueService(ref.watch(workerAttendanceRepositoryProvider)),
);

final deviceKeyStoreProvider = Provider<DeviceKeyStore>(
  (ref) => SharedPrefsDeviceKeyStore(),
);

final terminalScanServiceProvider = Provider<TerminalScanService>(
  (ref) => TerminalScanService(
    ref.watch(terminalScanRepositoryProvider),
    ref.watch(deviceKeyStoreProvider),
  ),
);

final terminalBindingProvider = FutureProvider.family<BindingStatus, String>(
  (ref, terminalUid) => TerminalBindingService(
    ref.watch(deviceKeyStoreProvider),
    ref.watch(terminalScanRepositoryProvider),
  ).ensureBound(terminalUid),
);

final terminalAdminServiceProvider = Provider<TerminalAdminService>(
  (ref) => TerminalAdminService(
    ref.watch(terminalRepositoryProvider),
    ref.watch(staffAccountCreatorProvider),
  ),
);

final attendanceAdminServiceProvider = Provider<AttendanceAdminService>(
  (ref) => AttendanceAdminService(ref.watch(attendanceAdminRepositoryProvider)),
);

final terminalsProvider = StreamProvider<List<AttendanceTerminal>>(
  (ref) => ref.watch(terminalRepositoryProvider).watchAll(),
);

final schedulesProvider = StreamProvider<List<Schedule>>(
  (ref) => ref.watch(attendanceAdminRepositoryProvider).watchSchedules(),
);

final myStateProvider = StreamProvider.family<AttendanceState?, String>(
  (ref, uid) => ref.watch(workerAttendanceRepositoryProvider).watchState(uid),
);

final myHistoryProvider = StreamProvider.family<List<AttendanceRecord>, String>(
  (ref, uid) => ref.watch(workerAttendanceRepositoryProvider).watchHistory(uid),
);

final myCorrectionsProvider =
    StreamProvider.family<List<CorrectionRequest>, String>(
  (ref, uid) =>
      ref.watch(workerAttendanceRepositoryProvider).watchCorrections(uid),
);

final tokenProvider = StreamProvider.family<QrToken?, String>(
  (ref, id) => ref.watch(workerAttendanceRepositoryProvider).watchToken(id),
);

final allCorrectionsProvider = StreamProvider<List<CorrectionRequest>>(
  (ref) => ref.watch(attendanceAdminRepositoryProvider).watchAllCorrections(),
);

/// Rango [from, to) de instantes UTC para consultar asistencias.
class DateRange extends Equatable {
  const DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  @override
  List<Object?> get props => [from, to];
}

final recordsProvider = StreamProvider.family<List<AttendanceRecord>, DateRange>(
  (ref, range) => ref
      .watch(attendanceAdminRepositoryProvider)
      .watchRange(range.from, range.to),
);
