import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../inventory/services/consumption_planner.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/services/order_policy.dart';
import '../../orders/models/restaurant_order.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../../users/models/app_user.dart';
import '../services/kitchen_policy.dart';
import '../widgets/force_ready_dialog.dart';

StatusTone kitchenTone(KitchenStatus status) => switch (status) {
  KitchenStatus.pendiente => StatusTone.warning,
  KitchenStatus.preparando => StatusTone.info,
  KitchenStatus.listo => StatusTone.success,
  KitchenStatus.entregado => StatusTone.neutral,
};

/// Tablero de cocina: los pedidos registrados en tres columnas (pendiente,
/// en preparación, listo), el más antiguo primero, con el tiempo de espera.
/// En pantallas angostas muestra una columna a la vez.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});
  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  static const _columns = [
    KitchenStatus.pendiente,
    KitchenStatus.preparando,
    KitchenStatus.listo,
  ];
  late final Timer _clock;
  KitchenStatus _narrow = KitchenStatus.pendiente;

  @override
  void initState() {
    super.initState();
    // Los minutos de espera avanzan solos, sin esperar a un cambio en Firestore.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) {
      return const Center(child: Text('Inicia sesión para ver la cocina.'));
    }
    final user = session.user;
    return OrderAsyncView(
      value: ref.watch(ordersProvider),
      onRetry: () => ref.invalidate(ordersProvider),
      builder: (orders) {
        final now = DateTime.now();
        final queues = {
          for (final s in _columns) s: KitchenPolicy.queue(orders, s),
        };
        return PageBody(
          maxWidth: 1400,
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 720;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'Cocina',
                    subtitle: 'Pedidos registrados, del más antiguo al más reciente. Hora de Lima.',
                  ),
                  if (!wide)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in _columns)
                          FilterPill(
                            label: '${s.label} (${queues[s]!.length})',
                            selected: s == _narrow,
                            onTap: () => setState(() => _narrow = s),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final s in _columns)
                                Expanded(
                                  child: _Column(
                                    status: s,
                                    orders: queues[s]!,
                                    user: user,
                                    now: now,
                                  ),
                                ),
                            ],
                          )
                        : _Column(
                            status: _narrow,
                            orders: queues[_narrow]!,
                            user: user,
                            now: now,
                            showTitle: false,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.status,
    required this.orders,
    required this.user,
    required this.now,
    this.showTitle = true,
  });
  final KitchenStatus status;
  final List<RestaurantOrder> orders;
  final AppUser user;
  final DateTime now;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                StatusPill(status.label, tone: kitchenTone(status)),
                const SizedBox(width: 8),
                Text(
                  '${orders.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        Expanded(
          child: orders.isEmpty
              ? const StateMessage(
                  icon: Icons.soup_kitchen,
                  title: 'Sin pedidos aquí.',
                )
              : ListView(
                  children: [
                    for (final o in orders)
                      _Ticket(order: o, user: user, now: now),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _Ticket extends ConsumerWidget {
  const _Ticket({required this.order, required this.user, required this.now});
  final RestaurantOrder order;
  final AppUser user;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = KitchenPolicy.minutesWaiting(order, now);
    final urgency = KitchenPolicy.urgency(minutes);
    final next = order.kitchen!.next;
    final canAdvance =
        next != null && KitchenPolicy.canAdvance(user, order, next);
    final accent = switch (urgency) {
      KitchenUrgency.normal => AppColors.line,
      KitchenUrgency.attention => AppColors.warnFg,
      KitchenUrgency.late => AppColors.dangerFg,
    };
    final registered = order.registeredAt;
    final byline = registered == null
        ? order.waiterName
        : '${order.waiterName} · registrado ${LimaTime.formatTime(registered)}';
    final items = ref.watch(orderItemsProvider(order.id));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: accent,
          width: urgency == KitchenUrgency.normal ? 1 : 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mesa ${order.tableId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                StatusPill(
                  '$minutes min',
                  tone: switch (urgency) {
                    KitchenUrgency.normal => StatusTone.neutral,
                    KitchenUrgency.attention => StatusTone.warning,
                    KitchenUrgency.late => StatusTone.danger,
                  },
                ),
              ],
            ),
            Text(
              byline,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
            const Divider(),
            items.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('No se pudo cargar el detalle.'),
              data: (list) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        item.notes.isEmpty
                            ? '${item.quantity} × ${item.name}'
                            : '${item.quantity} × ${item.name}\n   ↳ ${item.notes}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            if (canAdvance)
              Align(
                alignment: Alignment.centerRight,
                child: OperationButton(
                  label: switch (next) {
                    KitchenStatus.preparando => 'Empezar a preparar',
                    KitchenStatus.listo => 'Marcar listo',
                    _ => 'Marcar entregado',
                  },
                  onPressed: () async {
                    final service = ref.read(orderServiceProvider);
                    try {
                      await service.advanceKitchen(order, next, user.uid);
                    } on InsufficientStockFailure catch (e) {
                      // Solo la administración puede forzar «Listo» con motivo.
                      if (!OrderPolicy.admin(user) || !context.mounted) rethrow;
                      final reason = await showDialog<String>(
                        context: context,
                        builder: (_) =>
                            ForceReadyDialog(shortages: e.shortages),
                      );
                      if (reason == null) return;
                      await service.advanceKitchen(
                        order,
                        next,
                        user.uid,
                        forceReason: reason,
                      );
                    }
                  },
                ),
              )
            else if (order.kitchen == KitchenStatus.listo)
              const Text(
                'Listo: espera al mesero.',
                style: TextStyle(color: AppColors.successFg),
              ),
          ],
        ),
      ),
    );
  }
}
