import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../auth/controllers/auth_providers.dart';
import '../controllers/staff_providers.dart';
import '../models/staff_draft.dart';
import '../services/staff_service.dart';

/// Resumen del alta: qué correos de activación aceptó Firebase, aviso de
/// restricción y botón para enviar la bienvenida por WhatsApp (envío manual).
/// Solo se cierra con «Finalizar», para no perder estas opciones por un toque
/// accidental fuera del diálogo.
class CreatedStaffDialog extends ConsumerStatefulWidget {
  const CreatedStaffDialog({super.key, required this.draft, required this.result});

  final StaffDraft draft;
  final CreateStaffResult result;

  @override
  ConsumerState<CreatedStaffDialog> createState() => _CreatedStaffDialogState();
}

class _CreatedStaffDialogState extends ConsumerState<CreatedStaffDialog> {
  late bool _resetOk = widget.result.resetEmailSent;
  bool _retrying = false;
  String? _retryMessage;

  Future<void> _retryReset() async {
    setState(() {
      _retrying = true;
      _retryMessage = null;
    });
    final outcome = await ref
        .read(emailRequesterProvider)
        .sendPasswordReset(widget.draft.emailNormalizado);
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _resetOk = _resetOk || outcome.ok;
      _retryMessage = outcome.message;
    });
  }

  Future<void> _openWhatsApp() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(whatsAppInviteProvider).send(
          celular: widget.draft.celular, nombres: widget.draft.nombres);
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    Widget line(bool ok, String okText, String failText, {Widget? action}) =>
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(ok ? Icons.mark_email_read : Icons.error_outline,
              color: ok ? null : error),
          title: Text(ok ? okText : failText),
          subtitle: ok ? null : action,
        );
    final draft = widget.draft;
    return AlertDialog(
      title: const Text('Trabajador registrado'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${draft.nombres} ${draft.apellidos}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Estado: Pendiente de activación. Se activará cuando '
                'defina su contraseña y verifique su correo.'),
            const SizedBox(height: 8),
            line(
              _resetOk,
              'Correo para crear contraseña: Firebase aceptó el envío.',
              'No se confirmó el envío del correo para crear contraseña.',
              action: Align(
                alignment: Alignment.centerLeft,
                child: _retrying
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton(
                        onPressed: _retryReset,
                        child: const Text('Reintentar envío'),
                      ),
              ),
            ),
            line(
              widget.result.verificationSent,
              'Correo de verificación: Firebase aceptó el envío.',
              'No se confirmó la verificación: el trabajador podrá reenviarla '
                  'al iniciar sesión.',
            ),
            if (_retryMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_retryMessage!),
              ),
            if (widget.result.restriction != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Aviso: este documento tiene una restricción de recontratación '
                  'vigente. Consulta al Superadmin.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.chat),
          label: const Text('Enviar bienvenida por WhatsApp'),
          onPressed: _openWhatsApp,
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Finalizar'),
        ),
      ],
    );
  }
}
