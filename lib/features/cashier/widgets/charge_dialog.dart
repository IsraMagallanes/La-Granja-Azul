import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/controllers/order_providers.dart';
import '../../orders/models/order_item.dart';
import '../../orders/models/restaurant_order.dart';
import '../controllers/cash_providers.dart';
import '../models/cash_models.dart';

/// Cobro de un pedido entregado: detalle, total, método de pago y, en efectivo,
/// el monto recibido con su vuelto. Si el cobro falla el diálogo se queda
/// abierto con el motivo y la mesa sigue ocupada.
class ChargeDialog extends ConsumerStatefulWidget {
  const ChargeDialog({super.key, required this.order});
  final RestaurantOrder order;
  @override
  ConsumerState<ChargeDialog> createState() => _ChargeDialogState();
}

class _ChargeDialogState extends ConsumerState<ChargeDialog> {
  PaymentMethod _method = PaymentMethod.efectivo;
  final _received = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  Future<void> _charge(int total) async {
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated) return;
    final received = _method.isCash ? Money.parse(_received.text) : total;
    if (received == null) {
      setState(() => _error = 'Indica el efectivo recibido, p. ej. 50.00.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final change = await ref
          .read(cashServiceProvider)
          .charge(
            order: widget.order,
            box: ref.read(openBoxProvider).value,
            method: _method,
            receivedCents: received,
            actorUid: session.user.uid,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mesa ${widget.order.tableId} cobrada y liberada.'
            '${_method.isCash ? ' Vuelto: ${soles(change)}' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(orderItemsProvider(widget.order.id));
    final total = items.value == null ? null : orderTotal(items.value!);
    final received = Money.parse(_received.text);
    final change = total != null && received != null && received >= total
        ? received - total
        : null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('Cobrar · Mesa ${widget.order.tableId}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Atendió: ${widget.order.waiterName}'),
                const SizedBox(height: 8),
                items.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(ErrorMapper.map(e).message),
                  data: (list) => Column(
                    children: [
                      for (final item in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${item.quantity} × ${item.name}'),
                              ),
                              Text(soles(item.subtotalCents)),
                            ],
                          ),
                        ),
                      const Divider(),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Total',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Text(
                            soles(orderTotal(list)),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in PaymentMethod.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: m == _method,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _method = m),
                      ),
                  ],
                ),
                if (_method.isCash) ...[
                  TextField(
                    controller: _received,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Efectivo recibido (S/)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    change != null
                        ? 'Vuelto: ${soles(change)}'
                        : received != null && total != null
                        ? 'Falta ${soles(total - received)}'
                        : 'Vuelto: —',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: _busy || total == null ? null : () => _charge(total),
            child: Text(_busy ? 'Cobrando…' : 'Confirmar cobro'),
          ),
        ],
      ),
    );
  }
}
