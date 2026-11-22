import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../orders/models/order_item.dart';
import '../controllers/cash_providers.dart';
import '../models/cash_models.dart';
import '../services/cash_service.dart';

/// Ingreso o egreso de efectivo de la caja abierta (con su concepto).
class MovementDialog extends ConsumerStatefulWidget {
  const MovementDialog({super.key, required this.box, required this.type});
  final CashBox box;
  final MovementType type;
  @override
  ConsumerState<MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<MovementDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(cashServiceProvider)
          .addMovement(
            widget.box,
            widget.type,
            Money.parse(_amount.text)!,
            _concept.text,
            actorUid: session.user.uid,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Registrar ${widget.type.label.toLowerCase()}'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Monto (S/)'),
              validator: Money.validate,
            ),
            TextFormField(
              controller: _concept,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Concepto'),
              validator: CashValidation.concept,
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}

/// Cierre de caja: efectivo contado contra el esperado. Si no cuadra, exige
/// una nota. El cierre es definitivo.
class CloseBoxDialog extends ConsumerStatefulWidget {
  const CloseBoxDialog({
    super.key,
    required this.box,
    required this.payments,
    required this.movements,
  });
  final CashBox box;
  final List<Payment> payments;
  final List<CashMovement> movements;
  @override
  ConsumerState<CloseBoxDialog> createState() => _CloseBoxDialogState();
}

class _CloseBoxDialogState extends ConsumerState<CloseBoxDialog> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _close(CashSummary summary) async {
    final session = ref.read(sessionProvider).value;
    final counted = Money.parse(_counted.text);
    if (session is! Authenticated) return;
    if (counted == null) {
      setState(() => _error = 'Indica el efectivo contado, p. ej. 350.00.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(cashServiceProvider)
          .closeBox(
            widget.box,
            countedCents: counted,
            payments: widget.payments,
            movements: widget.movements,
            notes: _notes.text,
            actorUid: session.user.uid,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = CashSummary.from(
      initial: widget.box.initial,
      payments: widget.payments,
      movements: widget.movements,
    );
    final counted = Money.parse(_counted.text);
    final difference = counted == null ? null : counted - summary.expectedCash;
    Widget line(String label, int cents, {bool bold = false}) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : null),
          ),
        ),
        Text(
          soles(cents),
          style: TextStyle(fontWeight: bold ? FontWeight.w800 : null),
        ),
      ],
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Cerrar caja'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line('Fondo inicial', summary.initial),
                line('Ventas en efectivo', summary.cashSales),
                line('Ingresos', summary.income),
                line('Egresos', -summary.expenses),
                const Divider(),
                line('Efectivo esperado', summary.expectedCash, bold: true),
                const SizedBox(height: 4),
                Text(
                  'Otras ventas (tarjeta, Yape, Plin): ${soles(summary.otherSales)} · '
                  '${summary.salesCount} ventas',
                  style: const TextStyle(fontSize: 12),
                ),
                TextField(
                  controller: _counted,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Efectivo contado (S/)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  difference == null
                      ? 'Diferencia: —'
                      : difference == 0
                      ? 'Cuadra exactamente.'
                      : difference > 0
                      ? 'Sobran ${soles(difference)}'
                      : 'Faltan ${soles(-difference)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: difference == null || difference == 0
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                TextField(
                  controller: _notes,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: difference != null && difference != 0
                        ? 'Motivo de la diferencia (obligatorio)'
                        : 'Notas (opcional)',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
            onPressed: _busy ? null : () => _close(summary),
            child: Text(_busy ? 'Cerrando…' : 'Cerrar caja'),
          ),
        ],
      ),
    );
  }
}
