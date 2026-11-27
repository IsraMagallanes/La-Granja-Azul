import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance_models.dart';
import '../models/schedule.dart';
import '../repositories/attendance_repositories.dart';
import '../services/attendance_services.dart';

/// Se sobrescriben en `main.dart` con las implementaciones de Firebase.
final workerAttendanceRepositoryProvider = Provider<WorkerAttendanceRepository>(
  (ref) => throw UnimplementedError(
    'workerAttendanceRepositoryProvider sin override',
  ),
);

final qrGenerationRepositoryProvider = Provider<QrGenerationRepository>(
  (ref) =>
      throw UnimplementedError('qrGenerationRepositoryProvider sin override'),
);

final qrScanRepositoryProvider = Provider<QrScanRepository>(
  (ref) => throw UnimplementedError('qrScanRepositoryProvider sin override'),
);

final attendanceAdminRepositoryProvider = Provider<AttendanceAdminRepository>(
  (ref) => throw UnimplementedError(
    'attendanceAdminRepositoryProvider sin override',
  ),
);

final qrGenerationServiceProvider = Provider<QrGenerationService>(
  (ref) => QrGenerationService(ref.watch(qrGenerationRepositoryProvider)),
);

final attendanceSelfServiceProvider = Provider<AttendanceSelfService>(
  (ref) => AttendanceSelfService(ref.watch(workerAttendanceRepositoryProvider)),
);

final attendanceScanServiceProvider = Provider<AttendanceScanService>(
  (ref) => AttendanceScanService(ref.watch(qrScanRepositoryProvider)),
);

final attendanceAdminServiceProvider = Provider<AttendanceAdminService>(
  (ref) => AttendanceAdminService(ref.watch(attendanceAdminRepositoryProvider)),
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

final recordsProvider =
    StreamProvider.family<List<AttendanceRecord>, DateRange>(
      (ref, range) => ref
          .watch(attendanceAdminRepositoryProvider)
          .watchRange(range.from, range.to),
    );
