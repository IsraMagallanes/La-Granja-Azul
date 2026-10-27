import 'package:flutter/material.dart';

import '../../../core/time/lima_time.dart';
import '../../../core/validators/validators.dart';
import '../../staff/models/staff_member.dart';
import '../models/attendance_models.dart';
import 'pickers.dart';

class RegularizeInput {
  const RegularizeInput({
    required this.member,
    required this.entrada,
    required this.salida,
    required this.motivo,
    required this.supervised,
  });

  final StaffMember member;
  final DateTime entrada;
  final DateTime? salida;
  final String motivo;
  final bool supervised;
}

/// Regularización de marcaciones: motivo obligatorio. Sirve también para la
/// marcación supervisada de trabajadores sin celular.
class RegularizeDialog extends StatefulWidget {
  const RegularizeDialog({
    super.key,
    required this.candidates,
    this.record,
    this.initialMember,
  });

  /// Trabajadores sobre los que quien regulariza tiene permiso.
  final List<StaffMember> candidates;

  /// Registro a corregir; `null` crea uno nuevo.
  final AttendanceRecord? record;
  final StaffMember? initialMember;

  static Future<RegularizeInput?> show(
    BuildContext context, {
    required List<StaffMember> candidates,
    AttendanceRecord? record,
    StaffMember? initialMember,
  }) =>
      showDialog<RegularizeInput>(
        context: context,
        builder: (_) => RegularizeDialog(
          candidates: candidates,
          record: record,
          initialMember: initialMember,
        ),
      );

  @override
  State<RegularizeDialog> createState() => _RegularizeDialogState();
}

class _RegularizeDialogState extends State<RegularizeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  late StaffMember? _member = widget.initialMember ??
      widget.candidates.where((m) => m.uid == widget.record?.uid).firstOrNull;
  late DateTime? _entrada = widget.record?.entrada;
  late DateTime? _salida = widget.record?.salida;
  bool _supervised = false;
  String? _error;

  bool get _editing => widget.record != null;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_member == null || _entrada == null) {
      setState(() => _error = 'Selecciona el trabajador y la hora de entrada.');
      return;
    }
    Navigator.pop(
      context,
      RegularizeInput(
        member: _member!,
        entrada: _entrada!,
        salida: _salida,
        motivo: _motivo.text.trim(),
        supervised: _supervised,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Regularizar marcación' : 'Registrar marcación'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<StaffMember>(
                  initialValue: _member,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trabajador'),
                  items: [
                    for (final m in widget.candidates)
                      DropdownMenuItem(value: m, child: Text(m.nombreCompleto)),
                  ],
                  onChanged: _editing ? null : (v) => setState(() => _member = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Entrada (hora de Lima)'),
                  subtitle: Text(_entrada == null ? 'Sin definir' : LimaTime.formatDateTime(_entrada!)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final v = await pickLimaDateTime(context, initial: _entrada);
                    if (v != null) setState(() => _entrada = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Salida (opcional)'),
                  subtitle: Text(_salida == null ? 'Sin salida (jornada abierta)' : LimaTime.formatDateTime(_salida!)),
                  trailing: _salida == null
                      ? const Icon(Icons.schedule)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _salida = null),
                        ),
                  onTap: () async {
                    final v = await pickLimaDateTime(context, initial: _salida ?? _entrada);
                    if (v != null) setState(() => _salida = v);
                  },
                ),
                if (!_editing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _supervised,
                    onChanged: (v) => setState(() => _supervised = v ?? false),
                    title: const Text('Marcación supervisada'),
                    subtitle: const Text('Para quien no tiene celular: la realiza un responsable presente.'),
                  ),
                TextFormField(
                  controller: _motivo,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Motivo (obligatorio)'),
                  validator: Validators.motivo,
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
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
