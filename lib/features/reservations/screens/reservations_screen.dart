import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/services/order_policy.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../../orders/widgets/order_detail.dart';
import '../controllers/reservation_providers.dart';
import '../models/reservation.dart';
import '../widgets/reservation_editor.dart';

enum _View {
  today('Hoy'),
  upcoming('Próximas'),
  history('Historial');

  const _View(this.label);
  final String label;
}

StatusTone reservationTone(ReservationStatus status) => switch (status) {
  ReservationStatus.pendiente => StatusTone.warning,
  ReservationStatus.confirmada => StatusTone.info,
  ReservationStatus.cumplida => StatusTone.success,
  ReservationStatus.cancelada => StatusTone.danger,
  ReservationStatus.noAsistio => StatusTone.neutral,
};

class ReservationsScreen extends ConsumerStatefulWidget {
  const ReservationsScreen({super.key});
  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  _View _view = _View.today;

  List<Reservation> _filter(List<Reservation> all, DateTime now) {
    final today = LimaTime.dateKey(now);
    return switch (_view) {
      _View.today => [
        for (final r in all)
          if (LimaTime.dateKey(r.at) == today) r,
      ],
      _View.upcoming => [
        for (final r in all)
          if (r.status.open && LimaTime.dateKey(r.at).compareTo(today) > 0) r,
      ],
      _View.history => [
        for (final r in all.reversed)
          if (!r.status.open) r,
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) {
      return const Center(child: Text('Inicia sesión para ver reservaciones.'));
    }
    final canManage = OrderPolicy.canOpen(session.user);
    final now = DateTime.now();
    return OrderAsyncView(
      value: ref.watch(reservationsProvider),
      onRetry: () => ref.invalidate(reservationsProvider),
      builder: (all) {
        final shown = _filter(all, now);
        return PageBody(
          child: ListView(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'Reservaciones',
                      subtitle: 'Horas en Lima. Cada reservación ocupa la mesa 2 horas.',
                    ),
                  ),
                  if (canManage)
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva reservación'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const ReservationEditor(),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final v in _View.values)
                    FilterPill(
                      label: v.label,
                      selected: v == _view,
                      onTap: () => setState(() => _view = v),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const StateMessage(
                  icon: Icons.event_seat,
                  title: 'No hay reservaciones en esta vista.',
                ),
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReservationCard(
                    reservation: r,
                    canManage: canManage,
                    uid: session.user.uid,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReservationCard extends ConsumerWidget {
  const _ReservationCard({
    required this.reservation,
    required this.canManage,
    required this.uid,
  });
  final Reservation reservation;
  final bool canManage;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reservation;
    final service = ref.read(reservationServiceProvider);
    final pastDue = !DateTime.now().isBefore(r.at);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mesa ${r.tableId} · ${LimaTime.formatDateTime(r.at)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                StatusPill(r.status.label, tone: reservationTone(r.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${r.customer} · ${r.partySize} personas · ${r.phone}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            if (r.notes.isNotEmpty) Text('Notas: ${r.notes}'),
            if (r.cancelReason != null)
              Text('Motivo de cancelación: ${r.cancelReason}'),
            Text(
              'Registrada por ${r.createdByName}',
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
            if (r.orderId != null)
              TextButton(
                onPressed: () => showOrderDetail(context, r.orderId!),
                child: const Text('Ver pedido'),
              ),
            if (canManage && r.status.open)
              Wrap(
                children: [
                  if (r.status == ReservationStatus.pendiente)
                    OperationButton(
                      label: 'Confirmar',
                      onPressed: () => service.confirm(r),
                    ),
                  if (r.status == ReservationStatus.confirmada)
                    OperationButton(
                      label: 'Sentar y abrir pedido',
                      onPressed: () async {
                        final id = await service.seat(r, waiterUid: uid);
                        if (context.mounted) await showOrderDetail(context, id);
                      },
                    ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ReservationEditor(reservation: r),
                    ),
                    child: const Text('Editar'),
                  ),
                  if (pastDue)
                    OperationButton(
                      label: 'No asistió',
                      onPressed: () => service.markNoShow(r),
                    ),
                  OperationButton(
                    label: 'Cancelar',
                    onPressed: () async {
                      final reason = await showDialog<String>(
                        context: context,
                        builder: (_) => const ReasonDialog(
                          title: '¿Cancelar la reservación?',
                          action: 'Cancelar reservación',
                        ),
                      );
                      if (reason != null) await service.cancel(r, reason);
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
