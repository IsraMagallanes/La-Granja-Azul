import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/time/lima_time.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../users/models/app_user.dart';
import '../controllers/attendance_providers.dart';
import '../models/attendance_models.dart';
import '../services/attendance_services.dart';
import '../widgets/correction_request_dialog.dart';

/// App del trabajador: genera su QR de entrada o salida (temporal y de un solo
/// uso), ve su historial, su turno y solicita correcciones. Generar el QR no
/// registra asistencia; solo la terminal del restaurante lo hace.
class MyAttendanceScreen extends ConsumerStatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  ConsumerState<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends ConsumerState<MyAttendanceScreen> {
  IssuedQr? _qr;
  Timer? _timer;
  int _remaining = 0;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _issue(AppUser user, PunchType type, AttendanceState? state) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final issued = await ref
          .read(qrIssueServiceProvider)
          .issue(user, type, state: state);
      _timer?.cancel();
      setState(() {
        _qr = issued;
        _remaining = QrToken.lifetime.inSeconds;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = _qr!.expiresAt.difference(DateTime.now()).inSeconds;
        if (left <= 0) {
          _clear('El QR venció. Genera uno nuevo si aún no marcaste.');
        } else {
          setState(() => _remaining = left);
        }
      });
    } catch (e) {
      setState(() => _notice = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear(String? notice) {
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _qr = null;
      _notice = notice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final user = session.user;
    final state = ref.watch(myStateProvider(user.uid)).value;
    final history = ref.watch(myHistoryProvider(user.uid));
    final corrections = ref.watch(myCorrectionsProvider(user.uid)).value ?? const [];
    final schedules = ref.watch(schedulesProvider).value ?? const [];
    final schedule = schedules.where((s) => s.id == user.horarioId).firstOrNull;
    final open = state?.abierta ?? false;

    // Cuando la terminal consume el QR, se limpia y se confirma.
    if (_qr != null) {
      ref.listen(tokenProvider(_qr!.token.id), (_, next) {
        if (next.value?.used == true) {
          _clear('Registro confirmado por la terminal.');
        }
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(open ? 'Jornada en curso' : 'Sin jornada abierta',
                    style: Theme.of(context).textTheme.titleMedium),
                if (schedule != null)
                  Text('Turno: ${schedule.nombre} · ${schedule.horaInicio}–${schedule.horaFin}'
                      '${schedule.esNocturno ? ' (nocturno)' : ''}'),
                const SizedBox(height: 4),
                const Text(
                  'Genera el QR y muéstralo en la terminal del restaurante. '
                  'Dura 45 segundos y se usa una sola vez.',
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _busy || open ? null : () => _issue(user, PunchType.entrada, state),
                    icon: const Icon(Icons.login),
                    label: const Text('Generar QR de entrada'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy || !open ? null : () => _issue(user, PunchType.salida, state),
                    icon: const Icon(Icons.logout),
                    label: const Text('Generar QR de salida'),
                  ),
                ]),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_notice!),
                  ),
              ],
            ),
          ),
        ),
        if (_qr != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('QR de ${_qr!.token.tipo.label.toLowerCase()}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: _qr!.payload, size: 240),
                  ),
                  const SizedBox(height: 12),
                  Text('Vence en $_remaining s',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Mi historial',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _requestCorrection(user),
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
              : Column(children: [for (final r in records) _RecordTile(record: r)]),
        ),
        if (corrections.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Mis solicitudes', style: Theme.of(context).textTheme.titleMedium),
          for (final c in corrections)
            ListTile(
              dense: true,
              title: Text('${c.fecha} · ${c.tipo}'),
              subtitle: Text(c.respuesta == null ? c.motivo : '${c.motivo}\nRespuesta: ${c.respuesta}'),
              trailing: Chip(label: Text(c.estado.label)),
            ),
        ],
      ],
    );
  }

  Future<void> _requestCorrection(AppUser user) async {
    final result = await CorrectionRequestDialog.show(context);
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(qrIssueServiceProvider).requestCorrection(
            worker: user,
            fecha: result.fecha,
            tipo: result.tipo,
            motivo: result.motivo,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Solicitud enviada.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
    }
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final out = record.salida == null ? 'en curso' : LimaTime.formatTime(record.salida!);
    return ListTile(
      dense: true,
      leading: Icon(record.regularizada ? Icons.edit_calendar : Icons.qr_code_2),
      title: Text('${LimaTime.dateKey(record.entrada)} · '
          '${LimaTime.formatTime(record.entrada)} → $out'),
      subtitle: Text(record.regularizada
          ? '${record.origen.label}: ${record.motivo ?? ''}'
          : 'QR'),
    );
  }
}
