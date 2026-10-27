import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../attendance/widgets/schedule_picker.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/models/user_role.dart';
import '../controllers/staff_providers.dart';
import '../models/staff_member.dart';
import '../models/staff_status.dart';
import 'staff_form_dialog.dart';
import 'status_change_dialog.dart';

/// Ficha completa de un trabajador y sus acciones, filtradas por jerarquía.
class StaffDetailSheet extends ConsumerWidget {
  const StaffDetailSheet({super.key, required this.uid});

  final String uid;

  static Future<void> show(BuildContext context, String uid) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => StaffDetailSheet(uid: uid),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final members = ref.watch(staffListProvider).value ?? const [];
    final member = members.where((m) => m.uid == uid).firstOrNull;
    if (session is! Authenticated || member == null) {
      return const SizedBox(height: 120);
    }
    final actor = session.user;
    final policy = ref.watch(staffPolicyProvider);
    final canManage = policy.canManage(
        actorRole: actor.role, actorUid: actor.uid, target: member);
    final service = ref.read(staffServiceProvider);

    Future<void> run(Future<void> Function() action, String done) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        messenger.showSnackBar(SnackBar(content: Text(done)));
      } catch (e) {
        messenger
            .showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
      }
    }

    Future<void> changeStatus(StaffStatus target) async {
      final change = await StatusChangeDialog.show(context,
          member: member, target: target);
      if (change == null) return;
      await run(() => service.changeStatus(actor, member, change),
          'Estado actualizado.');
    }

    Future<void> edit() async {
      final draft = await StaffFormDialog.show(
        context,
        assignableRoles: policy.assignableRoles(actor.role).toList(),
        existing: member,
      );
      if (draft == null) return;
      await run(() => service.update(actor, member, draft), 'Datos guardados.');
    }

    Future<void> resendPassword() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 30),
        content: Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Solicitando el enlace a Firebase…'),
        ]),
      ));
      final outcome = await ref
          .read(emailRequesterProvider)
          .sendPasswordReset(member.email);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(outcome.message)));
    }

    final rows = <(String, String)>[
      if (member.incompleto)
        ('Ficha', 'Incompleta (perfil anterior a la Fase 3): falta documento y celular.'),
      if (!member.incompleto) (member.documentType.label, member.documento),
      ('Correo', member.email),
      if (member.celular.isNotEmpty) ('Celular', '+51 ${member.celular}'),
      if (member.celularAlterno != null)
        ('Celular alternativo', '+51 ${member.celularAlterno}'),
      ('Rol', member.role.label),
      ('Estado', member.pendienteActivacion ? 'Pendiente de activación' : member.estado.label),
      if (member.activadoEn != null)
        ('Activada', StaffMember.formatDate(member.activadoEn!)),
      if (member.bajaTipo != null) ('Último motivo', member.bajaTipo!.label),
      if (!member.incompleto) ('Ingreso', StaffMember.formatDate(member.fechaIngreso)),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.nombreCompleto,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(label,
                          style: Theme.of(context).textTheme.labelMedium),
                    ),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
            if (canManage) ...[
              const Divider(height: 32),
              SchedulePicker(member: member, actor: actor),
              if (actor.role == UserRole.superadmin &&
                  member.role == UserRole.admin)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Puede regularizar marcaciones'),
                  value: member.puedeRegularizar,
                  onChanged: (v) => run(
                    () => service.setRegularizationPermission(actor, member,
                        allowed: v),
                    'Permiso actualizado.',
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (member.activo)
                    OutlinedButton.icon(
                      onPressed: resendPassword,
                      icon: const Icon(Icons.mark_email_read),
                      label: const Text('Reenviar enlace de contraseña'),
                    ),
                  if (member.activo && member.celular.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => run(
                        () => ref.read(whatsAppInviteProvider).send(
                            celular: member.celular, nombres: member.nombres),
                        'Se abrió WhatsApp: envía el mensaje manualmente.',
                      ),
                      icon: const Icon(Icons.chat),
                      label: const Text('Enviar bienvenida por WhatsApp'),
                    ),
                  OutlinedButton.icon(
                    onPressed: edit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar'),
                  ),
                  if (member.estado == StaffStatus.activo) ...[
                    OutlinedButton.icon(
                      onPressed: () => changeStatus(StaffStatus.suspendido),
                      icon: const Icon(Icons.pause_circle),
                      label: const Text('Suspender'),
                    ),
                    FilledButton.icon(
                      onPressed: () => changeStatus(StaffStatus.baja),
                      icon: const Icon(Icons.person_remove),
                      label: const Text('Dar de baja'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: () => changeStatus(StaffStatus.activo),
                      icon: const Icon(Icons.how_to_reg),
                      label: const Text('Reactivar'),
                    ),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('No tienes permisos para modificar este perfil.'),
              ),
          ],
        ),
      ),
    );
  }
}
