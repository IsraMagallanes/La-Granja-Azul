import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../inventory/widgets/inventory_dialogs.dart' show showActionDialog;
import '../../orders/widgets/order_async_view.dart';
import '../../roles/models/user_role.dart';
import '../../staff/controllers/staff_providers.dart';
import '../controllers/utensil_providers.dart';
import '../models/utensil_models.dart';
import '../widgets/utensil_dialogs.dart';

String _soles(int cents) => 'S/ ${(cents / 100).toStringAsFixed(2)}';

bool _isAdmin(WidgetRef ref) {
  final session = ref.read(sessionProvider).value;
  return session is Authenticated && isAdminRole(session.user.role);
}

/// Utensilios: existencias, lo que tiene cada mesero y el historial. Lo usan
/// Mesero, Admin y Superadmin. Los costos y las valoraciones solo existen para
/// la administración: las pantallas que observan `utensilCostsProvider` se
/// construyen únicamente para ella.
class UtensilsScreen extends ConsumerWidget {
  const UtensilsScreen({super.key});

  static const _tabs = [
    ('Utensilios', Icons.restaurant),
    ('Por mesero', Icons.badge),
    ('Movimientos', Icons.swap_vert),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La administración mantiene el directorio de meseros alineado con el
    // personal (por si algún cambio anterior no lo actualizó).
    if (_isAdmin(ref)) {
      ref.listen(staffListProvider, (_, next) {
        final staff = next.value;
        if (staff == null) return;
        ref
            .read(utensilRepositoryProvider)
            .syncWaiterDirectory([
              for (final s in staff)
                if (s.role == UserRole.mesero)
                  WaiterRef(s.uid, s.nombreCompleto, active: s.estado.canAccess),
            ])
            .catchError((_) => 0);
      });
    }
    return _scaffold(context);
  }

  Widget _scaffold(BuildContext context) => DefaultTabController(
    length: _tabs.length,
    child: Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in _tabs) Tab(icon: Icon(t.$2), text: t.$1)],
          ),
        ),
        const Expanded(
          child: TabBarView(
            children: [UtensilsTab(), AssignmentsTab(), UtensilMovementsTab()],
          ),
        ),
      ],
    ),
  );
}

class UtensilsTab extends ConsumerStatefulWidget {
  const UtensilsTab({super.key});
  @override
  ConsumerState<UtensilsTab> createState() => _UtensilsTabState();
}

class _UtensilsTabState extends ConsumerState<UtensilsTab> {
  bool _onlyLow = false;

  @override
  Widget build(BuildContext context) {
    final admin = _isAdmin(ref);
    final assignments =
        ref.watch(utensilAssignmentsProvider).value ??
        const <UtensilAssignment>[];
    return OrderAsyncView(
      value: ref.watch(utensilsProvider),
      onRetry: () => ref.invalidate(utensilsProvider),
      builder: (all) {
        final low = all.where((u) => u.isLow).length;
        final shown = _onlyLow ? all.where((u) => u.isLow).toList() : all;
        return PageBody(
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Utensilios',
                subtitle: 'Disponibles y en uso. Las existencias solo cambian con un movimiento.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (admin)
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      onPressed: () =>
                          showActionDialog(context, const UtensilDialog()),
                      label: const Text('Nuevo utensilio'),
                    ),
                  FilterPill(
                    label: 'Todos (${all.length})',
                    selected: !_onlyLow,
                    onTap: () => setState(() => _onlyLow = false),
                  ),
                  FilterPill(
                    label: 'Stock bajo ($low)',
                    selected: _onlyLow,
                    onTap: () => setState(() => _onlyLow = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const StateMessage(
                  icon: Icons.restaurant,
                  title: 'No hay utensilios para mostrar.',
                ),
              for (final u in shown)
                _UtensilCard(
                  utensil: u,
                  assignments: assignments,
                  admin: admin,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UtensilCard extends StatelessWidget {
  const _UtensilCard({
    required this.utensil,
    required this.assignments,
    required this.admin,
  });
  final Utensil utensil;
  final List<UtensilAssignment> assignments;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final u = utensil;
    final kinds = [
      for (final k in UtensilKind.values)
        if (!k.adminOnly || admin) k,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    u.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (!u.active)
                  const StatusPill('Inactivo', tone: StatusTone.neutral)
                else if (u.available <= 0)
                  const StatusPill('Sin disponibles', tone: StatusTone.danger)
                else if (u.isLow)
                  const StatusPill('Stock bajo', tone: StatusTone.warning),
                if (admin) _AdminEditButton(utensil: u),
              ],
            ),
            Text(
              'Disponibles ${u.available} · En uso ${u.inUse} · Total ${u.total} · mínimo ${u.minStock}',
              style: const TextStyle(color: AppColors.inkMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in kinds)
                  OutlinedButton(
                    onPressed: u.active
                        ? () => showActionDialog(
                            context,
                            UtensilMovementDialog(
                              utensil: u,
                              kind: k,
                              assignments: assignments,
                            ),
                          )
                        : null,
                    child: Text(k.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Editar el catálogo con el costo vigente. Solo se construye para Admin y
/// Superadmin: es el único sitio de las existencias que lee `costosUtensilios`.
class _AdminEditButton extends ConsumerWidget {
  const _AdminEditButton({required this.utensil});
  final Utensil utensil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costs = ref.watch(utensilCostsProvider).value ?? const {};
    final current = utensil.costVersion == 0
        ? null
        : costs['${utensil.id}_${utensil.costVersion}'];
    return IconButton(
      tooltip: 'Editar',
      icon: const Icon(Icons.edit),
      onPressed: () => showActionDialog(
        context,
        UtensilDialog(utensil: utensil, currentCost: current),
      ),
    );
  }
}

class AssignmentsTab extends ConsumerWidget {
  const AssignmentsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = {
      for (final u in ref.watch(utensilsProvider).value ?? const <Utensil>[])
        u.id: u.name,
    };
    return OrderAsyncView(
      value: ref.watch(utensilAssignmentsProvider),
      onRetry: () => ref.invalidate(utensilAssignmentsProvider),
      builder: (all) {
        final byWaiter = <String, List<UtensilAssignment>>{};
        for (final a in all.where((a) => a.quantity > 0)) {
          byWaiter.putIfAbsent(a.waiterId, () => []).add(a);
        }
        return PageBody(
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Por mesero',
                subtitle: 'Lo que cada mesero tiene en uso ahora.',
              ),
              if (byWaiter.isEmpty)
                const StateMessage(
                  icon: Icons.badge,
                  title: 'Nadie tiene utensilios en uso.',
                ),
              for (final list in byWaiter.values)
                Card(
                  child: ListTile(
                    title: Text(
                      list.first.waiterName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        for (final a in list)
                          '${a.quantity} ${names[a.utensilId] ?? 'utensilio'}',
                      ].join(' · '),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class UtensilMovementsTab extends ConsumerWidget {
  const UtensilMovementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = _isAdmin(ref);
    return OrderAsyncView(
      value: ref.watch(utensilMovementsProvider),
      onRetry: () => ref.invalidate(utensilMovementsProvider),
      builder: (moves) => PageBody(
        child: ListView(
          children: [
            const SectionHeader(
              title: 'Movimientos',
              subtitle: 'Los últimos 100. Son de solo lectura: no se editan ni se borran.',
            ),
            if (moves.isEmpty)
              const StateMessage(
                icon: Icons.swap_vert,
                title: 'Aún no hay movimientos.',
              ),
            for (final m in moves)
              admin
                  ? _AdminMovementTile(movement: m)
                  : _MovementTile(movement: m),
          ],
        ),
      ),
    );
  }
}

String _detail(UtensilMovement m, [int? value]) =>
    '${m.byName}${m.at == null ? '' : ' · ${LimaTime.formatDateTime(m.at!)}'}'
    '${m.waiterName == null ? '' : '\nMesero: ${m.waiterName}'}'
    '${m.reason.isEmpty ? '' : '\n${m.reason}'}'
    '${value == null ? '' : '\nValor: ${_soles(value)}'}';

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, this.value});
  final UtensilMovement movement;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: Icon(
          m.kind == UtensilKind.entrega
              ? Icons.north_east
              : m.kind == UtensilKind.devolucion || m.kind == UtensilKind.alta
              ? Icons.south_west
              : Icons.report,
          color: m.kind.isLoss ? AppColors.dangerFg : null,
        ),
        title: Text('${m.kind.label} · ${m.utensilName}'),
        subtitle: Text(_detail(m, value)),
        trailing: Text(
          '${m.quantity}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Movimiento con la valoración de pérdidas, daños y deterioros. Solo para
/// Admin y Superadmin: lee `costosUtensilios`.
class _AdminMovementTile extends ConsumerWidget {
  const _AdminMovementTile({required this.movement});
  final UtensilMovement movement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costs = ref.watch(utensilCostsProvider).value ?? const {};
    return _MovementTile(
      movement: movement,
      value: movement.kind.isLoss ? lossValue(movement, costs) : null,
    );
  }
}
