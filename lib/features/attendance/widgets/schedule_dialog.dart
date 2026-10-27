import 'package:flutter/material.dart';

import '../models/schedule.dart';

class ScheduleInput {
  const ScheduleInput({
    required this.nombre,
    required this.horaInicio,
    required this.horaFin,
    required this.toleranciaMin,
    required this.dias,
    required this.activo,
  });

  final String nombre;
  final String horaInicio;
  final String horaFin;
  final int toleranciaMin;
  final List<int> dias;
  final bool activo;
}

/// Configuración de un horario: horas, tolerancia, días y turno nocturno
/// (cuando la hora de fin es menor o igual a la de inicio).
class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({super.key, this.existing});

  final Schedule? existing;

  static Future<ScheduleInput?> show(BuildContext context, {Schedule? existing}) =>
      showDialog<ScheduleInput>(
        context: context,
        builder: (_) => ScheduleDialog(existing: existing),
      );

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  static const _dayNames = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  late final _nombre = TextEditingController(text: widget.existing?.nombre);
  late final _tolerancia =
      TextEditingController(text: '${widget.existing?.toleranciaMin ?? 10}');
  late String _inicio = widget.existing?.horaInicio ?? '08:00';
  late String _fin = widget.existing?.horaFin ?? '17:00';
  late final Set<int> _dias = {...(widget.existing?.dias ?? const [1, 2, 3, 4, 5])};
  late bool _activo = widget.existing?.activo ?? true;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _tolerancia.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final current = Schedule.parseMinutes(start ? _inicio : _fin)!;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (t == null) return;
    final text = Schedule.formatMinutes(t.hour * 60 + t.minute);
    setState(() => start ? _inicio = text : _fin = text);
  }

  void _submit() {
    final tol = int.tryParse(_tolerancia.text.trim());
    final error = tol == null
        ? 'La tolerancia debe ser un número.'
        : Schedule.validate(
            nombre: _nombre.text,
            horaInicio: _inicio,
            horaFin: _fin,
            toleranciaMin: tol,
            dias: _dias.toList(),
          );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      ScheduleInput(
        nombre: _nombre.text.trim(),
        horaInicio: _inicio,
        horaFin: _fin,
        toleranciaMin: tol!,
        dias: _dias.toList()..sort(),
        activo: _activo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nocturno = Schedule.parseMinutes(_fin)! <= Schedule.parseMinutes(_inicio)!;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo horario' : 'Editar horario'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre del turno'),
              ),
              Row(children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inicio'),
                    subtitle: Text(_inicio),
                    onTap: () => _pick(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fin'),
                    subtitle: Text(_fin),
                    onTap: () => _pick(false),
                  ),
                ),
              ]),
              if (nocturno)
                const Text('Turno nocturno: termina al día siguiente.'),
              TextField(
                controller: _tolerancia,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tolerancia (minutos)'),
              ),
              const SizedBox(height: 12),
              const Text('Días en que inicia el turno'),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(_dayNames[i]),
                      selected: _dias.contains(i + 1),
                      onSelected: (v) =>
                          setState(() => v ? _dias.add(i + 1) : _dias.remove(i + 1)),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
