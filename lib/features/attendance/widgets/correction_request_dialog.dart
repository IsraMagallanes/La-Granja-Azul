import 'package:flutter/material.dart';

import '../../../core/time/lima_time.dart';
import '../../../core/validators/validators.dart';

class CorrectionInput {
  const CorrectionInput(this.fecha, this.tipo, this.motivo);

  final String fecha;
  final String tipo;
  final String motivo;
}

/// Solicitud de corrección del trabajador (no modifica la asistencia: la
/// resuelve quien está autorizado a regularizar).
class CorrectionRequestDialog extends StatefulWidget {
  const CorrectionRequestDialog({super.key});

  static Future<CorrectionInput?> show(BuildContext context) =>
      showDialog<CorrectionInput>(
        context: context,
        builder: (_) => const CorrectionRequestDialog(),
      );

  @override
  State<CorrectionRequestDialog> createState() => _CorrectionRequestDialogState();
}

class _CorrectionRequestDialogState extends State<CorrectionRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  DateTime _date = DateTime.now();
  String _tipo = 'entrada';

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar corrección'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha'),
                subtitle: Text(LimaTime.dateKey(_date)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 60)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Qué corregir'),
                items: const [
                  DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
                  DropdownMenuItem(value: 'salida', child: Text('Salida')),
                  DropdownMenuItem(value: 'ambas', child: Text('Entrada y salida')),
                ],
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              TextFormField(
                controller: _motivo,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Motivo'),
                validator: Validators.motivo,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              CorrectionInput(
                '${_date.year.toString().padLeft(4, '0')}-'
                '${_date.month.toString().padLeft(2, '0')}-'
                '${_date.day.toString().padLeft(2, '0')}',
                _tipo,
                _motivo.text.trim(),
              ),
            );
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
