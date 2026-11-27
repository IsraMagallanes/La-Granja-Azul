import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../cashier/models/cash_models.dart';
import '../../inventory/widgets/inventory_dialogs.dart' show ActionDialog;
import '../../roles/models/user_role.dart';
import '../../users/models/app_user.dart';
import '../controllers/utensil_providers.dart';
import '../models/utensil_models.dart';
import '../services/utensil_service.dart';

AppUser actorOf(WidgetRef ref) {
  final session = ref.read(sessionProvider).value;
  if (session is! Authenticated) {
    throw const AppFailure('Tu sesión ya no está activa.');
  }
  return session.user;
}

bool isAdminRole(UserRole? role) =>
    role == UserRole.admin || role == UserRole.superadmin;

/// Alta o edición del catálogo (solo Admin y Superadmin). El costo es opcional:
/// 0 = sin costo registrado; al cambiarlo se crea una versión nueva inmutable.
class UtensilDialog extends ConsumerStatefulWidget {
  const UtensilDialog({super.key, this.utensil, this.currentCost});
  final Utensil? utensil;

  /// Costo vigente (centavos) para mostrarlo al editar; null = sin costo.
  final int? currentCost;
  @override
  ConsumerState<UtensilDialog> createState() => _UtensilDialogState();
}

class _UtensilDialogState extends ConsumerState<UtensilDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.utensil?.name);
  late final _min = TextEditingController(
    text: widget.utensil == null ? '0' : '${widget.utensil!.minStock}',
  );
  late final _cost = TextEditingController(
    text: ((widget.currentCost ?? 0) / 100).toStringAsFixed(2),
  );
  late bool _active = widget.utensil?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() {
    final cost = Money.parse(_cost.text)!;
    final changed = cost != (widget.currentCost ?? 0);
    return ref
        .read(utensilServiceProvider)
        .saveUtensil(
          actorOf(ref),
          current: widget.utensil,
          name: _name.text,
          minStock: int.parse(_min.text.trim()),
          active: _active,
          newUnitCost: widget.utensil == null || changed ? cost : null,
        );
  }

  @override
  Widget build(BuildContext context) => ActionDialog(
    title: widget.utensil == null ? 'Nuevo utensilio' : 'Editar utensilio',
    validate: () => _form.currentState!.validate(),
    onSubmit: _save,
    content: Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: UtensilValidation.name,
          ),
          TextFormField(
            controller: _min,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Stock mínimo'),
            validator: (v) => RegExp(r'^\d{1,7}$').hasMatch((v ?? '').trim())
                ? null
                : 'Número entero (0 o más).',
          ),
          TextFormField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Costo por unidad (S/)',
              helperText:
                  '0 = costo no registrado. Solo lo ve la administración.',
            ),
            validator: (v) => Money.validate(v, allowZero: true),
          ),
          if (widget.utensil != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
        ],
      ),
    ),
  );
}

/// Registra un movimiento de un utensilio. Para los que afectan a un mesero
/// pide elegirlo: la entrega puede ir a cualquier mesero activo que el actor
/// conozca; el resto, solo a quien tiene unidades en uso.
class UtensilMovementDialog extends ConsumerStatefulWidget {
  const UtensilMovementDialog({
    super.key,
    required this.utensil,
    required this.kind,
    required this.assignments,
  });
  final Utensil utensil;
  final UtensilKind kind;
  final List<UtensilAssignment> assignments;
  @override
  ConsumerState<UtensilMovementDialog> createState() =>
      _UtensilMovementDialogState();
}

class _UtensilMovementDialogState extends ConsumerState<UtensilMovementDialog> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  WaiterRef? _waiter;
  bool _increase = true;

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Meseros elegibles: todos los activos del directorio mínimo (UID y nombre).
  /// Para devolver o dar de baja, solo quienes tienen utensilios asignados.
  List<WaiterRef> _candidates() {
    final actor = actorOf(ref);
    final holding = {
      for (final a in widget.assignments)
        if (a.utensilId == widget.utensil.id && a.quantity > 0)
          a.waiterId: WaiterRef(a.waiterId, a.waiterName),
    };
    if (widget.kind != UtensilKind.entrega) return holding.values.toList();
    final all = <String, WaiterRef>{
      for (final a in widget.assignments)
        a.waiterId: WaiterRef(a.waiterId, a.waiterName),
    };
    if (actor.role == UserRole.mesero) {
      all[actor.uid] = WaiterRef(actor.uid, actor.nombre);
    }
    for (final w in ref.watch(waiterDirectoryProvider).value ?? const []) {
      all[w.uid] = w;
    }
    return all.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final candidates = kind.toWaiter ? _candidates() : const <WaiterRef>[];
    return ActionDialog(
      title: '${kind.label} · ${widget.utensil.name}',
      validate: () => _form.currentState!.validate(),
      onSubmit: () => ref
          .read(utensilServiceProvider)
          .register(
            actorOf(ref),
            widget.utensil,
            kind,
            UtensilValidation.quantity(_qty.text)!,
            _reason.text,
            waiter: kind.toWaiter ? _waiter : null,
            increase: _increase,
          ),
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Disponibles: ${widget.utensil.available} · En uso: ${widget.utensil.inUse}',
            ),
            if (kind == UtensilKind.ajuste)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Sumar')),
                  ButtonSegment(value: false, label: Text('Restar')),
                ],
                selected: {_increase},
                onSelectionChanged: (s) => setState(() => _increase = s.first),
              ),
            if (kind.toWaiter)
              DropdownButtonFormField<WaiterRef>(
                initialValue: _waiter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mesero'),
                items: [
                  for (final w in candidates)
                    DropdownMenuItem(value: w, child: Text(w.name)),
                ],
                onChanged: (w) => setState(() => _waiter = w),
                validator: (v) => v == null
                    ? (candidates.isEmpty
                          ? 'No hay meseros con unidades en uso.'
                          : 'Elige al mesero.')
                    : null,
              ),
            TextFormField(
              controller: _qty,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              validator: UtensilValidation.quantityError,
            ),
            TextFormField(
              controller: _reason,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: kind.needsReason ? 'Motivo' : 'Motivo (opcional)',
              ),
              validator: (v) =>
                  kind.needsReason ? UtensilValidation.reason(v) : null,
            ),
          ],
        ),
      ),
    );
  }
}
