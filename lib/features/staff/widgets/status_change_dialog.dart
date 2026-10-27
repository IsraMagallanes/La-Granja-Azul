import 'package:flutter/material.dart';

import '../../../core/validators/validators.dart';
import '../models/staff_member.dart';
import '../models/staff_status.dart';
import '../models/status_change.dart';

/// Modal obligatorio para suspender, dar de baja o reactivar: exige el tipo de
/// motivo, el motivo escrito y una confirmación explícita.
class StatusChangeDialog extends StatefulWidget {
  const StatusChangeDialog({
    super.key,
    required this.member,
    required this.target,
  });

  final StaffMember member;
  final StaffStatus target;

  static Future<StatusChange?> show(
    BuildContext context, {
    required StaffMember member,
    required StaffStatus target,
  }) =>
      showDialog<StatusChange>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatusChangeDialog(member: member, target: target),
      );

  @override
  State<StatusChangeDialog> createState() => _StatusChangeDialogState();
}

class _StatusChangeDialogState extends State<StatusChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _detail = TextEditingController();
  LeaveReason? _reason;
  bool _confirmed = false;

  bool get _reactivating => widget.target == StaffStatus.activo;

  List<LeaveReason> get _options => widget.target == StaffStatus.suspendido
      ? const [LeaveReason.suspension, LeaveReason.otro]
      : const [LeaveReason.renuncia, LeaveReason.despido, LeaveReason.otro];

  String get _title => switch (widget.target) {
        StaffStatus.activo => 'Reactivar trabajador',
        StaffStatus.suspendido => 'Suspender trabajador',
        StaffStatus.baja => 'Dar de baja',
      };

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || !_confirmed) return;
    Navigator.pop(
      context,
      StatusChange(
        newStatus: widget.target,
        reason: _reactivating ? null : _reason,
        detail: _detail.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.member.nombreCompleto,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(_reactivating
                    ? 'Recupera el acceso a la aplicación.'
                    : 'Bloquea el acceso a la aplicación. La cuenta y el '
                        'historial se conservan.'),
                const SizedBox(height: 16),
                if (!_reactivating)
                  DropdownButtonFormField<LeaveReason>(
                    initialValue: _reason,
                    decoration:
                        const InputDecoration(labelText: 'Tipo de motivo'),
                    items: [
                      for (final r in _options)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    validator: (v) =>
                        v == null ? 'Selecciona un motivo.' : null,
                    onChanged: (v) => setState(() => _reason = v),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detail,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (confidencial)',
                    helperText: 'Solo lo verá el Superadmin.',
                  ),
                  validator: Validators.motivo,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  title: const Text('Confirmo que deseo realizar esta acción.'),
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
        FilledButton(
          onPressed: _confirmed ? _submit : null,
          child: Text(_reactivating ? 'Reactivar' : 'Confirmar'),
        ),
      ],
    );
  }
}
