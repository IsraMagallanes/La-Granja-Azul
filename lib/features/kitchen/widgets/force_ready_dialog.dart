import 'package:flutter/material.dart';

import '../../inventory/models/inventory_models.dart';
import '../../inventory/services/consumption_planner.dart';

/// Pide a un administrador el motivo para marcar «Listo» un pedido al que le
/// falta stock. Devuelve el motivo, o null si cancela.
class ForceReadyDialog extends StatefulWidget {
  const ForceReadyDialog({super.key, required this.shortages});
  final List<StockShortage> shortages;

  static const minReason = 10;

  static String? validate(String? v) {
    final length = (v ?? '').trim().length;
    return length < minReason || length > 200
        ? 'Motivo de $minReason a 200 caracteres.'
        : null;
  }

  @override
  State<ForceReadyDialog> createState() => _ForceReadyDialogState();
}

class _ForceReadyDialogState extends State<ForceReadyDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Falta stock'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Si fuerzas el «Listo» se descuenta solo lo disponible (el stock '
              'nunca queda negativo) y la excepción queda registrada con tu '
              'nombre, el motivo y los faltantes.',
            ),
            const SizedBox(height: 8),
            for (final s in widget.shortages)
              Text(
                '• ${s.supply.name}: necesita ${Qty.format(s.needed)} '
                '${s.supply.unit.label}, hay ${s.supply.stockLabel} '
                '(faltan ${Qty.format(s.missing)})',
              ),
            TextFormField(
              controller: _reason,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo'),
              validator: ForceReadyDialog.validate,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Forzar «Listo»'),
      ),
    ],
  );
}
