import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../staff/controllers/staff_providers.dart';
import '../../staff/models/staff_member.dart';
import '../../users/models/app_user.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';
import '../models/schedule.dart';
import '../services/attendance_report.dart';
import '../services/regularization.dart';
import '../widgets/regularize_dialog.dart';
import '../widgets/schedule_dialog.dart';

/// Administración de asistencia (hora de Lima, sin sanciones automáticas):
/// resumen del día, historial con filtros, horarios y correcciones.
class AttendanceAdminScreen extends ConsumerWidget {
  const AttendanceAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Hoy'),
              Tab(text: 'Historial'),
              Tab(text: 'Horarios'),
              Tab(text: 'Correcciones'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _TodayTab(actor: session.user),
                _HistoryTab(actor: session.user),
                _SchedulesTab(actor: session.user),
                _CorrectionsTab(actor: session.user),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ErrorMapper.map(error).message)));

/// Personal sobre el que [actor] puede regularizar (activos, jerarquía).
List<StaffMember> _candidates(WidgetRef ref, AppUser actor, List<StaffMember> all) {
  final policy = ref.read(staffPolicyProvider);
  return [
    for (final m in all)
      if (m.activo && m.uid != actor.uid && policy.canAssign(actor.role, m.role)) m,
  ]..sort((a, b) => a.apellidos.compareTo(b.apellidos));
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab({required this.actor});

  final AppUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = LimaTime.startOfDay(now);
    // Desde ayer: incluye turnos nocturnos que cruzan la medianoche.
    final range = DateRange(
      today.subtract(const Duration(days: 1)),
      today.add(const Duration(days: 1)),
    );
    final records = ref.watch(recordsProvider(range));
    final staff = ref.watch(staffListProvider).value ?? const [];
    final schedules = {
      for (final s in ref.watch(schedulesProvider).value ?? const <Schedule>[]) s.id: s,
    };
    return records.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
      data: (recs) {
        final report = AttendanceReport.build(
          now: now,
          staff: staff,
          schedules: schedules,
          records: recs,
        );
        final names = {for (final m in staff) m.uid: m.nombreCompleto};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Stat('Presentes', report.present.length, Icons.how_to_reg),
              _Stat('Puntuales', report.onTime.length, Icons.check_circle),
              _Stat('Tardanzas', report.late.length, Icons.watch_later),
              _Stat('Ausencias', report.absent.length, Icons.person_off),
            ]),
            const SizedBox(height: 16),
            _Section('Presentes ahora', [
              for (final r in report.present)
                ListTile(
                  dense: true,
                  title: Text(names[r.uid] ?? r.uid),
                  subtitle: Text('Entrada ${LimaTime.formatDateTime(r.entrada)}'),
                ),
            ]),
            _Section('Tardanzas', [
              for (final d in report.late)
                ListTile(
                  dense: true,
                  title: Text(d.staff.nombreCompleto),
                  subtitle: Text('${d.lateMinutes} min tarde · turno ${d.schedule.nombre}'),
                ),
            ]),
            _Section('Ausencias', [
              for (final d in report.absent)
                ListTile(
                  dense: true,
                  title: Text(d.staff.nombreCompleto),
                  subtitle: Text('Turno ${d.schedule.nombre} ${d.schedule.horaInicio}–${d.schedule.horaFin}'),
                ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Informativo: no se aplican sanciones ni descuentos automáticos.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$value', style: Theme.of(context).textTheme.headlineSmall),
                Text(label),
              ]),
            ]),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (children.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('—')),
          ...children,
          const SizedBox(height: 8),
        ],
      );
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({required this.actor});

  final AppUser actor;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  late DateTime _from =
      LimaTime.startOfDay(DateTime.now()).subtract(const Duration(days: 7));
  late DateTime _to = LimaTime.startOfDay(DateTime.now()).add(const Duration(days: 1));
  String? _uid;
  String _filter = 'todos';

  Future<void> _pickRange() async {
    final w1 = LimaTime.wall(_from);
    final w2 = LimaTime.wall(_to.subtract(const Duration(days: 1)));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime(w1.year, w1.month, w1.day),
        end: DateTime(w2.year, w2.month, w2.day),
      ),
    );
    if (picked == null) return;
    setState(() {
      _from = LimaTime.instant(picked.start.year, picked.start.month, picked.start.day);
      _to = LimaTime.instant(picked.end.year, picked.end.month, picked.end.day)
          .add(const Duration(days: 1));
    });
  }

  Future<void> _regularize({AttendanceRecord? record}) async {
    final actor = widget.actor;
    final staff = ref.read(staffListProvider).value ?? const <StaffMember>[];
    final candidates = _candidates(ref, actor, staff);
    final input = await RegularizeDialog.show(context, candidates: candidates, record: record);
    if (input == null || !mounted) return;
    final service = ref.read(attendanceAdminServiceProvider);
    try {
      if (record == null) {
        await service.regularizeNew(
          actor,
          targetUid: input.member.uid,
          targetRole: input.member.role,
          entrada: input.entrada,
          salida: input.salida,
          motivo: input.motivo,
          supervised: input.supervised,
        );
      } else {
        await service.regularizeExisting(
          actor,
          record: record,
          targetRole: input.member.role,
          entrada: input.entrada,
          salida: input.salida,
          motivo: input.motivo,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Marcación registrada y auditada.')));
      }
    } catch (e) {
      if (mounted) _toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordsProvider(DateRange(_from, _to)));
    final staff = ref.watch(staffListProvider).value ?? const <StaffMember>[];
    final schedules = {
      for (final s in ref.watch(schedulesProvider).value ?? const <Schedule>[]) s.id: s,
    };
    final byUid = {for (final m in staff) m.uid: m};
    final canRegularize = const Regularization().canRegularize(widget.actor);

    return Scaffold(
      floatingActionButton: canRegularize
          ? FloatingActionButton.extended(
              onPressed: _regularize,
              icon: const Icon(Icons.edit_calendar),
              label: const Text('Registrar marcación'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text('${LimaTime.dateKey(_from)} → '
                    '${LimaTime.dateKey(_to.subtract(const Duration(days: 1)))}'),
              ),
              DropdownButton<String?>(
                value: _uid,
                hint: const Text('Trabajador'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  for (final m in staff)
                    DropdownMenuItem(value: m.uid, child: Text(m.nombreCompleto)),
                ],
                onChanged: (v) => setState(() => _uid = v),
              ),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todas')),
                  DropdownMenuItem(value: 'tardanzas', child: Text('Tardanzas')),
                  DropdownMenuItem(value: 'regularizadas', child: Text('Regularizadas')),
                  DropdownMenuItem(value: 'abiertas', child: Text('Jornadas abiertas')),
                ],
                onChanged: (v) => setState(() => _filter = v!),
              ),
            ]),
          ),
          Expanded(
            child: records.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
              data: (all) {
                final list = all.where((r) {
                  if (_uid != null && r.uid != _uid) return false;
                  final schedule = schedules[byUid[r.uid]?.horarioId];
                  return switch (_filter) {
                    'tardanzas' => schedule != null && schedule.lateMinutes(r.entrada) > 0,
                    'regularizadas' => r.regularizada,
                    'abiertas' => r.abierta,
                    _ => true,
                  };
                }).toList();
                if (list.isEmpty) return const Center(child: Text('Sin registros.'));
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = list[i];
                    final member = byUid[r.uid];
                    final late = schedules[member?.horarioId]?.lateMinutes(r.entrada) ?? 0;
                    return ListTile(
                      title: Text(member?.nombreCompleto ?? r.uid),
                      subtitle: Text(
                        '${LimaTime.formatDateTime(r.entrada)} → '
                        '${r.salida == null ? 'en curso' : LimaTime.formatTime(r.salida!)}'
                        '${late > 0 ? ' · $late min tarde' : ''}'
                        '${r.regularizada ? '\n${r.origen.label}: ${r.motivo ?? ''}' : ''}',
                      ),
                      isThreeLine: r.regularizada,
                      trailing: canRegularize && member != null
                          ? IconButton(
                              tooltip: 'Regularizar',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _regularize(record: r),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulesTab extends ConsumerWidget {
  const _SchedulesTab({required this.actor});

  final AppUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);

    Future<void> edit([Schedule? existing]) async {
      final input = await ScheduleDialog.show(context, existing: existing);
      if (input == null || !context.mounted) return;
      try {
        await ref.read(attendanceAdminServiceProvider).saveSchedule(
              actor,
              id: existing?.id ?? '',
              nombre: input.nombre,
              horaInicio: input.horaInicio,
              horaFin: input.horaFin,
              toleranciaMin: input.toleranciaMin,
              dias: input.dias,
              activo: input.activo,
            );
      } catch (e) {
        if (context.mounted) _toast(context, e);
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.more_time),
        label: const Text('Nuevo horario'),
      ),
      body: schedules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No hay horarios configurados.'))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final s in items)
                    ListTile(
                      title: Text(s.nombre),
                      subtitle: Text(
                        '${s.horaInicio}–${s.horaFin}${s.esNocturno ? ' (nocturno)' : ''}'
                        ' · tolerancia ${s.toleranciaMin} min'
                        ' · ${s.activo ? 'activo' : 'inactivo'}',
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () => edit(s),
                    ),
                ],
              ),
      ),
    );
  }
}

class _CorrectionsTab extends ConsumerWidget {
  const _CorrectionsTab({required this.actor});

  final AppUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(allCorrectionsProvider);
    final staff = ref.watch(staffListProvider).value ?? const <StaffMember>[];
    final names = {for (final m in staff) m.uid: m.nombreCompleto};
    final canResolve = const Regularization().canRegularize(actor);

    Future<void> resolve(CorrectionRequest r, bool approved) async {
      final controller = TextEditingController();
      final answer = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(approved ? 'Aprobar solicitud' : 'Rechazar solicitud'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Respuesta al trabajador'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (answer == null || !context.mounted) return;
      try {
        await ref.read(attendanceAdminServiceProvider).resolveCorrection(
              actor, r, approved: approved, respuesta: answer);
      } catch (e) {
        if (context.mounted) _toast(context, e);
      }
    }

    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
      data: (items) => items.isEmpty
          ? const Center(child: Text('Sin solicitudes.'))
          : ListView(
              children: [
                for (final r in items)
                  ListTile(
                    title: Text('${names[r.uid] ?? r.uid} · ${r.fecha} · ${r.tipo}'),
                    subtitle: Text(r.motivo),
                    trailing: r.estado == CorrectionStatus.pendiente && canResolve
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Aprobar',
                              icon: const Icon(Icons.check),
                              onPressed: () => resolve(r, true),
                            ),
                            IconButton(
                              tooltip: 'Rechazar',
                              icon: const Icon(Icons.close),
                              onPressed: () => resolve(r, false),
                            ),
                          ])
                        : Chip(label: Text(r.estado.label)),
                  ),
              ],
            ),
    );
  }
}
