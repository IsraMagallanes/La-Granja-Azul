import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/time/lima_time.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/models/order_item.dart';
import '../../orders/widgets/order_async_view.dart';
import '../controllers/cash_providers.dart';
import '../models/cash_models.dart';
import '../widgets/cash_dialogs.dart';

/// Apertura, movimientos y cierre de la caja.
class CashView extends ConsumerWidget {
  const CashView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAsyncView(
    value: ref.watch(openBoxProvider),
    onRetry: () => ref.invalidate(openBoxProvider),
    builder: (box) => PageBody(
      child: box == null ? const _OpenBox() : _OpenBoxPanel(box: box),
    ),
  );
}

class _OpenBox extends ConsumerStatefulWidget {
  const _OpenBox();
  @override
  ConsumerState<_OpenBox> createState() => _OpenBoxState();
}

class _OpenBoxState extends ConsumerState<_OpenBox> {
  final _initial = TextEditingController(text: '0.00');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _initial.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final session = ref.read(sessionProvider).value;
    final cents = Money.parse(_initial.text);
    if (session is! Authenticated) return;
    if (cents == null) {
      setState(() => _error = 'Indica el fondo inicial, p. ej. 100.00.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(cashServiceProvider)
          .openBox(cents, actorUid: session.user.uid);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SectionHeader(
        title: 'Caja',
        subtitle:
            'La caja está cerrada. Ábrela con el efectivo del fondo inicial.',
      ),
      PanelCard(
        title: 'Abrir caja',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _initial,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fondo inicial en efectivo (S/)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open),
              onPressed: _busy ? null : _open,
              label: Text(_busy ? 'Abriendo…' : 'Abrir caja'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _OpenBoxPanel extends ConsumerWidget {
  const _OpenBoxPanel({required this.box});
  final CashBox box;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(boxPaymentsProvider(box.id));
    final movements = ref.watch(boxMovementsProvider(box.id));
    final paymentList = payments.value ?? const <Payment>[];
    final movementList = movements.value ?? const <CashMovement>[];
    final summary = CashSummary.from(
      initial: box.initial,
      payments: paymentList,
      movements: movementList,
    );
    final loaded = payments.hasValue && movements.hasValue;
    final opened = box.openedAt == null
        ? ''
        : ' · desde ${LimaTime.formatDateTime(box.openedAt!)}';
    return ListView(
      children: [
        SectionHeader(
          title: 'Caja abierta',
          subtitle: 'Abierta por ${box.openedByName}$opened (hora de Lima).',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (icon, label, value) in [
              (Icons.savings, 'Fondo inicial', summary.initial),
              (Icons.payments, 'Ventas en efectivo', summary.cashSales),
              (Icons.credit_card, 'Tarjeta / Yape / Plin', summary.otherSales),
              (Icons.south_west, 'Ingresos', summary.income),
              (Icons.north_east, 'Egresos', summary.expenses),
              (
                Icons.account_balance_wallet,
                'Efectivo esperado',
                summary.expectedCash,
              ),
            ])
              SizedBox(
                width: 210,
                child: StatCard(icon: icon, label: label, value: soles(value)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.south_west),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    MovementDialog(box: box, type: MovementType.ingreso),
              ),
              label: const Text('Registrar ingreso'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.north_east),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    MovementDialog(box: box, type: MovementType.egreso),
              ),
              label: const Text('Registrar egreso'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.lock),
              onPressed: loaded
                  ? () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => CloseBoxDialog(
                        box: box,
                        payments: paymentList,
                        movements: movementList,
                      ),
                    )
                  : null,
              label: const Text('Cerrar caja'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PanelCard(
          title: 'Movimientos de la caja',
          child: movementList.isEmpty
              ? const Text('Sin ingresos ni egresos registrados.')
              : Column(
                  children: [
                    for (final m in movementList)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          m.type == MovementType.ingreso
                              ? Icons.south_west
                              : Icons.north_east,
                          color: m.type == MovementType.ingreso
                              ? AppColors.successFg
                              : AppColors.dangerFg,
                        ),
                        title: Text(m.concept),
                        subtitle: Text(
                          '${m.byName}${m.at == null ? '' : ' · ${LimaTime.formatTime(m.at!)}'}',
                        ),
                        trailing: Text(
                          '${m.type == MovementType.egreso ? '−' : '+'}${soles(m.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
