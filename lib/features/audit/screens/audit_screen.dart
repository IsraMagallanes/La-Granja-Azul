import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/time/lima_time.dart';
import '../../staff/controllers/staff_providers.dart';

/// Superadmin: registro de acciones administrativas (quién, cuándo y qué
/// campos cambiaron). No muestra motivos confidenciales ni datos personales.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditEntriesProvider);
    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(ErrorMapper.map(e).message)),
      data: (list) => list.isEmpty
          ? const Center(child: Text('Sin actividad registrada.'))
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = list[i];
                return ListTile(
                  dense: true,
                  title: Text('${e.accion} · ${e.actorNombre}'),
                  subtitle: Text(
                    '${e.creadoEn == null ? '…' : LimaTime.formatDateTime(e.creadoEn!)}'
                    ' · objetivo ${e.objetivo}'
                    '${e.campos.isEmpty ? '' : ' · campos: ${e.campos.join(', ')}'}',
                  ),
                );
              },
            ),
    );
  }
}
