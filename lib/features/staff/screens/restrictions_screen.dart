import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/validators/validators.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../users/models/app_user.dart';
import '../controllers/staff_providers.dart';
import '../models/rehire_restriction.dart';
import '../models/staff_member.dart';
import '../services/restriction_service.dart';

final restrictionServiceProvider = Provider<RestrictionService>(
  (ref) => RestrictionService(
    ref.watch(restrictionRepositoryProvider),
    policy: ref.watch(staffPolicyProvider),
  ),
);

/// Superadmin: restricciones de recontratación por DNI/CE. Informativas: no
/// bloquean automáticamente ninguna contratación.
class RestrictionsScreen extends ConsumerWidget {
  const RestrictionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final actor = session.user;
    final items = ref.watch(restrictionsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.block),
        label: const Text('Nueva restricción'),
        onPressed: () => _establish(context, ref, actor),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No hay restricciones registradas.'))
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final r in list)
                    ListTile(
                      leading: Icon(r.activa ? Icons.block : Icons.check_circle_outline),
                      title: Text(r.documento),
                      subtitle: Text(r.activa
                          ? 'Activa · revisar el ${r.revisarEn}'
                              '${r.needsReview(DateTime.now()) ? ' (REVISIÓN PENDIENTE)' : ''}'
                          : 'Levantada'),
                      onTap: () => _detail(context, ref, actor, r),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _establish(BuildContext context, WidgetRef ref, AppUser actor) async {
    final input = await showDialog<({String doc, String why, DateTime review})>(
      context: context,
      builder: (_) => const _EstablishDialog(),
    );
    if (input == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(restrictionServiceProvider).establish(
            actor,
            documento: input.doc,
            justification: input.why,
            reviewOn: input.review,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
    }
  }

  Future<void> _detail(BuildContext context, WidgetRef ref, AppUser actor,
      RehireRestriction r) async {
    final service = ref.read(restrictionServiceProvider);
    String? why;
    try {
      why = await service.justificationOf(actor, r.documento);
    } catch (_) {
      why = null;
    }
    if (!context.mounted) return;
    final controller = TextEditingController();
    final lift = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Restricción · ${r.documento}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.activa ? 'Activa. Revisar el ${r.revisarEn}.' : 'Levantada.'),
            const SizedBox(height: 8),
            Text('Última justificación (confidencial):\n${why ?? '—'}'),
            if (r.activa) ...[
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Justificación para levantarla'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          if (r.activa)
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Levantar')),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (lift != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.lift(actor, documento: r.documento, justification: text);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
    }
  }
}

class _EstablishDialog extends StatefulWidget {
  const _EstablishDialog();

  @override
  State<_EstablishDialog> createState() => _EstablishDialogState();
}

class _EstablishDialogState extends State<_EstablishDialog> {
  final _formKey = GlobalKey<FormState>();
  final _doc = TextEditingController();
  final _why = TextEditingController();
  DateTime _review = DateTime.now().add(const Duration(days: 180));

  @override
  void dispose() {
    _doc.dispose();
    _why.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restricción de recontratación'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _doc,
                decoration: const InputDecoration(labelText: 'DNI o carné de extranjería'),
                validator: RestrictionService.validateDocument,
              ),
              TextFormField(
                controller: _why,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Justificación (confidencial)'),
                validator: Validators.motivo,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha de revisión'),
                subtitle: Text(StaffMember.formatDate(_review)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _review,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setState(() => _review = picked);
                },
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
            Navigator.pop(context, (doc: _doc.text, why: _why.text, review: _review));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
