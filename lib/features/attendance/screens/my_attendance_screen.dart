import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/controllers/role_providers.dart';
import '../../roles/models/permission.dart';
import '../../users/models/app_user.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';
import '../widgets/correction_request_dialog.dart';

/// Mi asistencia: estado de la jornada, historial, turno y correcciones. Aquí
/// NO se genera ningún QR: quien lo muestra (Superadmin, Admin, Cajero) lo hace
/// en «Generar QR»; quien registra su entrada o salida (Mesero, Cocina, Cajero)
/// lo hace escaneándolo en «Escanear asistencia».
class MyAttendanceScreen extends ConsumerWidget {
  const MyAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final user = session.user;
    final permissions = ref.watch(permissionServiceProvider);
    final canScan = permissions.can(user.role, Permission.scanAttendanceQr);
    final canGenerate = permissions.can(
      user.role,
      Permission.generateAttendanceQr,
    );
    final state = ref.watch(myStateProvider(user.uid)).value;
    final history = ref.watch(myHistoryProvider(user.uid));
    final corrections =
        ref.watch(myCorrectionsProvider(user.uid)).value ?? const [];
    final schedules = ref.watch(schedulesProvider).value ?? const [];
    final schedule = schedules.where((s) => s.id == user.horarioId).firstOrNull;
    final open = state?.abierta ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open ? 'Jornada en curso' : 'Sin jornada abierta',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (schedule != null)
                  Text(
                    'Turno: ${schedule.nombre} · ${schedule.horaInicio}–${schedule.horaFin}'
                    '${schedule.esNocturno ? ' (nocturno)' : ''}',
                  ),
                if (canScan) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Escanea el QR de asistencia: la app registra tu entrada '
                    'o tu salida automáticamente según tu jornada.',
                  ),
                  if (!session.onShift)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Registra tu entrada para acceder a tus módulos de trabajo.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
                if (canScan || canGenerate) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (canScan)
                        FilledButton.icon(
                          onPressed: () => context.go(AppRoute.scanQr.path),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Escanear QR de asistencia'),
                        ),
                      if (canGenerate)
                        OutlinedButton.icon(
                          onPressed: () => context.go(AppRoute.generateQr.path),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Mostrar QR de asistencia'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Mi historial',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _requestCorrection(context, ref, user),
              icon: const Icon(Icons.edit_note),
              label: const Text('Solicitar corrección'),
            ),
          ],
        ),
        history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(ErrorMapper.map(e).message),
          data: (records) => records.isEmpty
              ? const Text('Aún no tienes marcaciones.')
              : Column(
                  children: [for (final r in records) _RecordTile(record: r)],
                ),
        ),
        if (corrections.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Mis solicitudes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final c in corrections)
            ListTile(
              dense: true,
              title: Text('${c.fecha} · ${c.tipo}'),
              subtitle: Text(
                c.respuesta == null
                    ? c.motivo
                    : '${c.motivo}\nRespuesta: ${c.respuesta}',
              ),
              trailing: Chip(label: Text(c.estado.label)),
            ),
        ],
      ],
    );
  }

  Future<void> _requestCorrection(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    final result = await CorrectionRequestDialog.show(context);
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(attendanceSelfServiceProvider)
          .requestCorrection(
            worker: user,
            fecha: result.fecha,
            tipo: result.tipo,
            motivo: result.motivo,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Solicitud enviada.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorMapper.map(e).message)),
      );
    }
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final out = record.salida == null
        ? 'en curso'
        : LimaTime.formatTime(record.salida!);
    return ListTile(
      dense: true,
      leading: Icon(
        record.regularizada ? Icons.edit_calendar : Icons.qr_code_2,
      ),
      title: Text(
        '${LimaTime.dateKey(record.entrada)} · '
        '${LimaTime.formatTime(record.entrada)} → $out',
      ),
      subtitle: Text(
        record.regularizada
            ? '${record.origen.label}: ${record.motivo ?? ''}'
            : 'QR',
      ),
    );
  }
}
