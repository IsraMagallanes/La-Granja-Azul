import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/models/user_role.dart';
import '../../staff/controllers/staff_providers.dart';
import '../../staff/models/staff_member.dart';
import '../../staff/models/staff_status.dart';
import '../../staff/services/staff_list_query.dart';
import '../../staff/widgets/created_staff_dialog.dart';
import '../../staff/widgets/staff_detail_sheet.dart';
import '../../staff/widgets/staff_form_dialog.dart';

/// Gestión de personal: lista con búsqueda, filtros y paginación de 20. Los
/// datos personales se muestran enmascarados; el detalle los revela solo a
/// quien administra.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! Authenticated) return const SizedBox.shrink();
    final actor = session.user;
    final query = ref.watch(staffQueryProvider);
    final staff = ref.watch(staffListProvider);
    final roles = ref.watch(staffPolicyProvider).assignableRoles(actor.role);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo trabajador'),
        onPressed: () => _create(context, ref, roles.toList()),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
        data: (all) {
          final filtered = query.filter(all);
          final pageItems = query.pageOf(filtered);
          final pages = query.pageCount(filtered.length);
          final page = query.page.clamp(0, pages - 1);
          return Column(
            children: [
              _Filters(query: query),
              Expanded(
                child: pageItems.isEmpty
                    ? const Center(child: Text('Sin resultados.'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: pageItems.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _StaffTile(
                          member: pageItems[i],
                          onTap: () => StaffDetailSheet.show(
                              context, pageItems[i].uid),
                        ),
                      ),
              ),
              _Pager(
                page: page,
                pages: pages,
                total: filtered.length,
                onPage: (p) => ref
                    .read(staffQueryProvider.notifier)
                    .update((q) => q.copyWith(page: p)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    List<UserRole> roles,
  ) async {
    final session = ref.read(sessionProvider).value;
    if (session is! Authenticated) return;
    final draft = await StaffFormDialog.show(context, assignableRoles: roles);
    if (draft == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await runWithProgress(
        context,
        message: 'Registrando trabajador y solicitando los correos a Firebase…',
        task: () => ref.read(staffServiceProvider).create(session.user, draft),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CreatedStaffDialog(draft: draft, result: result),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
    }
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.query});

  final StaffListQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void update(StaffListQuery Function(StaffListQuery) f) =>
        ref.read(staffQueryProvider.notifier).update(f);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre, documento o correo',
              ),
              onChanged: (v) => update((q) => q.copyWith(text: v, page: 0)),
            ),
          ),
          DropdownButton<UserRole?>(
            value: query.role,
            hint: const Text('Rol'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos los roles')),
              for (final r in UserRole.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) => update((q) => q.copyWith(role: () => v, page: 0)),
          ),
          DropdownButton<StaffStatus?>(
            value: query.status,
            hint: const Text('Estado'),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos los estados')),
              for (final s in StaffStatus.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) =>
                update((q) => q.copyWith(status: () => v, page: 0)),
          ),
        ],
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.member, required this.onTap});

  final StaffMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: member.activo ? scheme.primaryContainer : scheme.errorContainer,
        child: Icon(member.activo ? Icons.person : Icons.person_off),
      ),
      title: Text(member.nombreCompleto),
      subtitle: Text(
        member.incompleto
            ? '${member.role.label} · Ficha incompleta'
            : '${member.role.label} · ${member.documentType.label} '
                '${member.documentoEnmascarado} · ${member.celularEnmascarado}',
      ),
      trailing: Chip(
        label: Text(member.pendienteActivacion
            ? 'Pendiente de activación'
            : member.estado.label),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int pages;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Anterior',
            onPressed: page > 0 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Página ${page + 1} de $pages · $total trabajadores'),
          IconButton(
            tooltip: 'Siguiente',
            onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
