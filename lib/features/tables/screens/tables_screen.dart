import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../../core/time/lima_time.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/services/order_policy.dart';
import '../../orders/widgets/order_detail.dart';
import '../../orders/widgets/operation_button.dart';
import '../../orders/widgets/order_async_view.dart';
import '../../reservations/controllers/reservation_providers.dart';
import '../../reservations/models/reservation.dart';
import '../controllers/table_providers.dart';
import '../models/restaurant_table.dart';
import '../widgets/table_editor.dart';

class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) {
      return const Center(child: Text('Inicia sesión para consultar mesas.'));
    }
    final admin = OrderPolicy.admin(session.user);
    final canOpen = OrderPolicy.canOpen(session.user);
    // Las reservaciones solo adornan el mosaico: si no se pueden leer, se omiten.
    final reservations =
        ref.watch(reservationsProvider).whenOrNull(data: (v) => v) ??
        const <Reservation>[];
    final now = DateTime.now();
    Reservation? nextFor(String tableId) {
      final today = LimaTime.dateKey(now);
      return reservations
          .where(
            (r) =>
                r.tableId == tableId &&
                r.status.open &&
                LimaTime.dateKey(r.at) == today &&
                r.at.add(Reservation.stay).isAfter(now),
          )
          .firstOrNull;
    }

    return OrderAsyncView(
      value: ref.watch(tablesProvider),
      onRetry: () => ref.invalidate(tablesProvider),
      builder: (tables) => PageBody(
        child: ListView(
          children: [
            Row(
              children: [
                const Expanded(
                  child: SectionHeader(
                    title: 'Mesas',
                    subtitle: 'Verde: libre · rojo: ocupada · gris: inactiva',
                  ),
                ),
                if (admin)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva mesa'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const TableEditor(),
                    ),
                  ),
              ],
            ),
            if (tables.isEmpty)
              const StateMessage(
                icon: Icons.table_restaurant,
                title: 'Aún no hay mesas registradas.',
              ),
            LayoutBuilder(
              builder: (context, c) {
                final cols = (c.maxWidth / 200).floor().clamp(1, 6);
                final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final table in tables)
                      SizedBox(
                        width: w,
                        child: _TableTile(
                          table: table,
                          admin: admin,
                          canOpen: canOpen,
                          uid: session.user.uid,
                          reservation: nextFor(table.id),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TableTile extends ConsumerWidget {
  const _TableTile({
    required this.table,
    required this.admin,
    required this.canOpen,
    required this.uid,
    this.reservation,
  });

  final Reservation? reservation;
  final RestaurantTable table;
  final bool admin;
  final bool canOpen;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (bg, border, fg) = !table.active
        ? (AppColors.neutralBg, AppColors.line, AppColors.neutralFg)
        : table.occupied
        ? (AppColors.dangerBg, const Color(0xFFF0A8A8), AppColors.dangerFg)
        : (
            const Color(0xFFE3F6E1),
            const Color(0xFF9ED89A),
            AppColors.successFg,
          );
    final status = !table.active
        ? 'Inactiva'
        : table.occupied
        ? 'Ocupada'
        : 'Libre';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(Icons.table_restaurant, color: fg),
          const SizedBox(height: 4),
          Text(
            'Mesa ${table.id}',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Text(
            '${table.capacity} personas',
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
          ),
          Text(
            status,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
          if (reservation != null && table.active)
            Text(
              'Reservada ${LimaTime.formatTime(reservation!.at)} · ${reservation!.customer}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.infoFg, fontSize: 12),
            ),
          if (admin)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => TableEditor(table: table),
              ),
              child: const Text('Editar mesa'),
            ),
          if (canOpen && table.active && !table.occupied)
            OperationButton(
              label: 'Abrir pedido',
              onPressed: () async {
                final id = await ref
                    .read(orderServiceProvider)
                    .open(table.id, uid);
                if (context.mounted) await showOrderDetail(context, id);
              },
            ),
        ],
      ),
    );
  }
}
