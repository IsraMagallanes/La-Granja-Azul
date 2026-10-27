import '../../../core/time/lima_time.dart';
import '../../staff/models/staff_member.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';

enum DayStatus {
  puntual('Puntual'),
  tardanza('Tardanza'),
  ausente('Ausente'),
  pendiente('Aún no inicia');

  const DayStatus(this.label);

  final String label;
}

/// Situación de un trabajador con turno en el día consultado.
class WorkerDay {
  const WorkerDay({
    required this.staff,
    required this.schedule,
    required this.status,
    this.record,
    this.lateMinutes = 0,
  });

  final StaffMember staff;
  final Schedule schedule;
  final DayStatus status;
  final AttendanceRecord? record;
  final int lateMinutes;
}

/// Resumen del día (hora de Lima): presentes, tardanzas y ausencias. Solo
/// informa; no aplica sanciones ni descuentos.
class AttendanceReport {
  const AttendanceReport({
    required this.days,
    required this.present,
  });

  /// Trabajadores con turno ese día.
  final List<WorkerDay> days;

  /// Jornadas abiertas (incluye turnos nocturnos iniciados el día anterior).
  final List<AttendanceRecord> present;

  List<WorkerDay> get late =>
      [for (final d in days) if (d.status == DayStatus.tardanza) d];
  List<WorkerDay> get absent =>
      [for (final d in days) if (d.status == DayStatus.ausente) d];
  List<WorkerDay> get onTime =>
      [for (final d in days) if (d.status == DayStatus.puntual) d];

  /// Antelación con la que se acepta una entrada para un turno.
  static const earlyWindow = Duration(hours: 4);

  static AttendanceReport build({
    required DateTime now,
    required Iterable<StaffMember> staff,
    required Map<String, Schedule> schedules,
    required Iterable<AttendanceRecord> records,
  }) {
    final today = LimaTime.startOfDay(now);
    final byUid = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      byUid.putIfAbsent(r.uid, () => []).add(r);
    }

    final days = <WorkerDay>[];
    for (final member in staff) {
      if (!member.activo) continue;
      final schedule = schedules[member.horarioId];
      if (schedule == null || !schedule.activo || !schedule.appliesOn(today)) {
        continue;
      }
      final start = schedule.startOn(today);
      final end = schedule.endOn(today);
      final record = (byUid[member.uid] ?? const <AttendanceRecord>[])
          .where((r) =>
              !r.entrada.isBefore(start.subtract(earlyWindow)) &&
              !r.entrada.isAfter(end))
          .fold<AttendanceRecord?>(
              null, (a, b) => a == null || b.entrada.isBefore(a.entrada) ? b : a);

      if (record != null) {
        final late = schedule.lateMinutes(record.entrada);
        days.add(WorkerDay(
          staff: member,
          schedule: schedule,
          record: record,
          lateMinutes: late,
          status: late > 0 ? DayStatus.tardanza : DayStatus.puntual,
        ));
      } else {
        final deadline = start.add(Duration(minutes: schedule.toleranciaMin));
        days.add(WorkerDay(
          staff: member,
          schedule: schedule,
          status: now.isAfter(deadline) ? DayStatus.ausente : DayStatus.pendiente,
        ));
      }
    }
    days.sort((a, b) => a.staff.apellidos.compareTo(b.staff.apellidos));

    return AttendanceReport(
      days: days,
      present: [for (final r in records) if (r.abierta) r],
    );
  }
}
