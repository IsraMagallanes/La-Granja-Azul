import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/validators/validators.dart';
import '../../roles/models/user_role.dart';
import '../models/document_type.dart';
import '../models/staff_draft.dart';
import '../models/staff_member.dart';

/// Formulario de alta o edición. En edición el documento y el correo son de
/// solo lectura (los índices de unicidad no se modifican).
class StaffFormDialog extends StatefulWidget {
  const StaffFormDialog({
    super.key,
    required this.assignableRoles,
    this.existing,
  });

  final List<UserRole> assignableRoles;
  final StaffMember? existing;

  static Future<StaffDraft?> show(
    BuildContext context, {
    required List<UserRole> assignableRoles,
    StaffMember? existing,
  }) =>
      showDialog<StaffDraft>(
        context: context,
        builder: (_) => StaffFormDialog(
          assignableRoles: assignableRoles,
          existing: existing,
        ),
      );

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombres = TextEditingController(text: widget.existing?.nombres);
  late final _apellidos =
      TextEditingController(text: widget.existing?.apellidos);
  late final _documento =
      TextEditingController(text: widget.existing?.documento);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _celular = TextEditingController(text: widget.existing?.celular);
  late final _alterno =
      TextEditingController(text: widget.existing?.celularAlterno);
  late DocumentType _type = widget.existing?.documentType ?? DocumentType.dni;
  late UserRole? _role = widget.existing?.role ??
      (widget.assignableRoles.isEmpty ? null : widget.assignableRoles.last);
  late DateTime _ingreso = widget.existing?.fechaIngreso ?? DateTime.now();

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [
      _nombres,
      _apellidos,
      _documento,
      _email,
      _celular,
      _alterno,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _ingreso,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _ingreso = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _role == null) return;
    Navigator.pop(
      context,
      StaffDraft(
        nombres: _nombres.text.trim(),
        apellidos: _apellidos.text.trim(),
        documentType: _type,
        documento: _documento.text,
        email: _email.text,
        celular: _celular.text.trim(),
        celularAlterno: _alterno.text,
        role: _role!,
        fechaIngreso: _ingreso,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(_editing ? 'Editar trabajador' : 'Nuevo trabajador'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombres,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                  validator: (v) => Validators.persona(v, field: 'Los nombres'),
                ),
                TextFormField(
                  controller: _apellidos,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
                  validator: (v) =>
                      Validators.persona(v, field: 'Los apellidos'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<DocumentType>(
                  initialValue: _type,
                  decoration:
                      const InputDecoration(labelText: 'Tipo de documento'),
                  items: [
                    for (final t in DocumentType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged:
                      _editing ? null : (v) => setState(() => _type = v!),
                ),
                TextFormField(
                  controller: _documento,
                  enabled: !_editing,
                  decoration: InputDecoration(labelText: _type.label),
                  keyboardType: _type == DocumentType.dni
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: _type == DocumentType.dni ? digits : null,
                  maxLength: _type == DocumentType.dni ? 8 : 12,
                  validator: _type.validate,
                ),
                TextFormField(
                  controller: _email,
                  enabled: !_editing,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                TextFormField(
                  controller: _celular,
                  decoration: const InputDecoration(
                      labelText: 'Celular', prefixText: '+51 '),
                  keyboardType: TextInputType.phone,
                  inputFormatters: digits,
                  maxLength: 9,
                  validator: Validators.celular,
                ),
                TextFormField(
                  controller: _alterno,
                  decoration: const InputDecoration(
                    labelText: 'Celular alternativo / emergencia (opcional)',
                    prefixText: '+51 ',
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: digits,
                  maxLength: 9,
                  validator: Validators.celularOpcional,
                ),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [
                    for (final r in widget.assignableRoles)
                      DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  validator: (v) => v == null ? 'Selecciona un rol.' : null,
                  onChanged: (v) => setState(() => _role = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de ingreso'),
                  subtitle: Text(StaffMember.formatDate(_ingreso)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
