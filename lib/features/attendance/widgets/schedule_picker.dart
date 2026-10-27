import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../staff/controllers/staff_providers.dart';
import '../../staff/models/staff_member.dart';
import '../../users/models/app_user.dart';
import '../controllers/attendance_providers.dart';

/// Asigna un horario al trabajador (en su ficha).
class SchedulePicker extends ConsumerWidget {
  const SchedulePicker({super.key, required this.member, required this.actor});

  final StaffMember member;
  final AppUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = (ref.watch(schedulesProvider).value ?? const [])
        .where((s) => s.activo || s.id == member.horarioId)
        .toList();
    final current = schedules.any((s) => s.id == member.horarioId)
        ? member.horarioId
        : null;
    return DropdownButtonFormField<String?>(
      initialValue: current,
      decoration: const InputDecoration(labelText: 'Horario asignado'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Sin horario')),
        for (final s in schedules)
          DropdownMenuItem(
            value: s.id,
            child: Text('${s.nombre} (${s.horaInicio}–${s.horaFin})'),
          ),
      ],
      onChanged: (id) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref.read(staffServiceProvider).assignSchedule(actor, member, id);
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(ErrorMapper.map(e).message)));
        }
      },
    );
  }
}
