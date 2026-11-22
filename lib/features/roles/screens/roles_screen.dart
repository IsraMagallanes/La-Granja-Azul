import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/ui_kit.dart';
import '../controllers/role_providers.dart';
import '../models/permission.dart';
import '../models/user_role.dart';

/// Superadmin: consulta de la matriz de roles y permisos por módulo y acción.
/// Es de solo lectura a propósito: la matriz vive en el código
/// (`PermissionService`) y se replica en `firestore.rules`; cambiarla desde la
/// app dejaría ambas desalineadas.
class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  UserRole _role = UserRole.mesero;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(permissionServiceProvider);
    final exempt = service.isShiftExempt(_role);
    final modules = [
      for (final m in AppModule.values)
        if (service.actionsOf(_role, m).isNotEmpty) m,
    ];

    return SingleChildScrollView(
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Roles y permisos',
              subtitle:
                  'Consulta de la matriz vigente. Solo lectura: se define '
                  'en el código y en las reglas de Firestore.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in UserRole.values)
                  FilterPill(
                    label: role.label,
                    selected: role == _role,
                    onTap: () => setState(() => _role = role),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PanelCard(
              title: 'Acceso por asistencia',
              trailing: StatusPill(
                exempt ? 'Exento' : 'Requiere entrada',
                tone: exempt ? StatusTone.info : StatusTone.warning,
              ),
              child: Text(
                exempt
                    ? '${_role.label} no necesita registrar entrada: accede a sus '
                          'módulos en cualquier momento.'
                    : '${_role.label} accede a sus módulos operativos (mesas, '
                          'pedidos, cocina, caja, inventario) solo con la entrada '
                          'registrada; al registrar la salida pierde ese acceso. '
                          '«Mi asistencia» siempre está disponible.',
              ),
            ),
            const SizedBox(height: 16),
            PanelCard(
              title: 'Permisos de ${_role.label}',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Módulo')),
                    for (final a in PermissionAction.values)
                      DataColumn(label: Text(a.label)),
                  ],
                  rows: [
                    for (final m in modules)
                      DataRow(
                        cells: [
                          DataCell(Text(m.label)),
                          for (final a in PermissionAction.values)
                            DataCell(
                              service.canDo(_role, m, a)
                                  ? Icon(
                                      Icons.check_circle,
                                      semanticLabel: 'Permitido: ${a.label}',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    )
                                  : Icon(
                                      Icons.remove,
                                      semanticLabel: 'Sin permiso: ${a.label}',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
