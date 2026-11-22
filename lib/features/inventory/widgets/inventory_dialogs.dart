import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../cashier/models/cash_models.dart';
import '../../roles/models/user_role.dart';
import '../controllers/inventory_providers.dart';
import '../models/inventory_models.dart';
import '../services/inventory_service.dart';

bool actorIsAdminOf(WidgetRef ref) {
  final session = ref.read(sessionProvider).value;
  return session is Authenticated &&
      (session.user.role == UserRole.admin ||
          session.user.role == UserRole.superadmin);
}

String actorUidOf(WidgetRef ref) {
  final session = ref.read(sessionProvider).value;
  if (session is! Authenticated) {
    throw const AppFailure('Tu sesión ya no está activa.');
  }
  return session.user.uid;
}

/// Marco común de los diálogos del inventario: bloquea mientras guarda, deja el
/// diálogo abierto con el motivo si falla y se cierra solo si salió bien.
class ActionDialog extends StatefulWidget {
  const ActionDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onSubmit,
    this.submitLabel = 'Guardar',
    this.validate,
  });
  final String title;
  final Widget content;
  final String submitLabel;
  final Future<void> Function() onSubmit;
  final bool Function()? validate;
  @override
  State<ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<ActionDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (widget.validate != null && !widget.validate!()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorMapper.map(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.content,
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Guardando…' : widget.submitLabel),
        ),
      ],
    ),
  );
}

Future<bool?> showActionDialog(BuildContext context, Widget dialog) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => dialog,
    );

/// Alta o edición de un insumo. En edición no cambia la unidad ni el stock.
class SupplyDialog extends ConsumerStatefulWidget {
  const SupplyDialog({super.key, this.supply});
  final Supply? supply;
  @override
  ConsumerState<SupplyDialog> createState() => _SupplyDialogState();
}

class _SupplyDialogState extends ConsumerState<SupplyDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supply?.name);
  late final _min = TextEditingController(
    text: widget.supply == null ? '' : Qty.format(widget.supply!.minStock),
  );
  late final _cost = TextEditingController(
    text: widget.supply == null
        ? ''
        : (widget.supply!.unitCost / 100).toStringAsFixed(2),
  );
  late SupplyUnit _unit = widget.supply?.unit ?? SupplyUnit.kg;
  late bool _active = widget.supply?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = ref.read(inventoryServiceProvider);
    final min = Qty.parse(_min.text)!;
    final cost = Money.parse(_cost.text)!;
    final supply = widget.supply;
    if (supply == null) {
      await service.createSupply(_name.text, _unit, min, cost);
    } else {
      await service.editSupply(
        supply,
        name: _name.text,
        minStock: min,
        unitCost: cost,
        active: _active,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ActionDialog(
    title: widget.supply == null ? 'Nuevo insumo' : 'Editar insumo',
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
            validator: (v) => InventoryValidation.name(v),
          ),
          DropdownButtonFormField<SupplyUnit>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unidad'),
            items: [
              for (final u in SupplyUnit.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: widget.supply == null
                ? (u) => setState(() => _unit = u!)
                : null,
          ),
          TextFormField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Stock mínimo (${_unit.label})',
            ),
            validator: (v) => Qty.validate(v, allowZero: true),
          ),
          TextFormField(
            controller: _cost,
            // El costo de un insumo existente lo corrige solo la administración;
            // Almacén lo actualiza al recibir compras.
            readOnly: widget.supply != null && !actorIsAdminOf(ref),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Costo por ${_unit.label} (S/)',
            ),
            validator: (v) => Money.validate(v, allowZero: true),
          ),
          if (widget.supply != null)
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

/// Entrada, salida, merma o ajuste de stock de un insumo.
class StockMoveDialog extends ConsumerStatefulWidget {
  const StockMoveDialog({super.key, required this.supply, required this.kind});
  final Supply supply;
  final MovementKind kind;
  @override
  ConsumerState<StockMoveDialog> createState() => _StockMoveDialogState();
}

class _StockMoveDialogState extends ConsumerState<StockMoveDialog> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  bool _increase = true;

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ActionDialog(
      title: '${widget.kind.label} · ${widget.supply.name}',
      validate: () => _form.currentState!.validate(),
      onSubmit: () => ref
          .read(inventoryServiceProvider)
          .moveStock(
            widget.supply,
            widget.kind,
            Qty.parse(_qty.text)!,
            _reason.text,
            increase: _increase,
            actorUid: actorUidOf(ref),
          ),
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock actual: ${widget.supply.stockLabel}'),
            if (widget.kind == MovementKind.ajuste)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Sumar')),
                  ButtonSegment(value: false, label: Text('Restar')),
                ],
                selected: {_increase},
                onSelectionChanged: (s) => setState(() => _increase = s.first),
              ),
            TextFormField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Cantidad (${widget.supply.unit.label})',
              ),
              validator: Qty.validate,
            ),
            TextFormField(
              controller: _reason,
              maxLength: 120,
              decoration: InputDecoration(labelText: 'Motivo'),
              validator: InventoryValidation.reason,
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta o edición de un proveedor.
class SupplierDialog extends ConsumerStatefulWidget {
  const SupplierDialog({super.key, this.supplier});
  final Supplier? supplier;
  @override
  ConsumerState<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<SupplierDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _ruc = TextEditingController(text: widget.supplier?.ruc);
  late final _phone = TextEditingController(text: widget.supplier?.phone);
  late final _contact = TextEditingController(text: widget.supplier?.contact);
  late bool _active = widget.supplier?.active ?? true;

  @override
  void dispose() {
    for (final c in [_name, _ruc, _phone, _contact]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ActionDialog(
    title: widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
    validate: () => _form.currentState!.validate(),
    onSubmit: () => ref
        .read(inventoryServiceProvider)
        .saveSupplier(
          widget.supplier,
          name: _name.text,
          ruc: _ruc.text,
          phone: _phone.text,
          contact: _contact.text,
          active: _active,
        ),
    content: Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nombre o razón social',
            ),
            validator: (v) => InventoryValidation.name(v, max: 80),
          ),
          TextFormField(
            controller: _ruc,
            keyboardType: TextInputType.number,
            maxLength: 11,
            decoration: const InputDecoration(labelText: 'RUC (opcional)'),
            validator: InventoryValidation.ruc,
          ),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          TextFormField(
            controller: _contact,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Contacto'),
          ),
          if (widget.supplier != null)
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

/// Editor de líneas (insumo + cantidad + costo) compartido por compras; las
/// recetas usan el mismo con costo oculto.
class LineDraft {
  LineDraft(this.supply, {String qty = '', String cost = ''})
    : qty = TextEditingController(text: qty),
      cost = TextEditingController(text: cost);
  Supply supply;
  final TextEditingController qty;
  final TextEditingController cost;
  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// Nueva compra a un proveedor (queda pendiente hasta recibirla).
class PurchaseDialog extends ConsumerStatefulWidget {
  const PurchaseDialog({
    super.key,
    required this.supplies,
    required this.suppliers,
  });
  final List<Supply> supplies;
  final List<Supplier> suppliers;
  @override
  ConsumerState<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends ConsumerState<PurchaseDialog> {
  final _form = GlobalKey<FormState>();
  Supplier? _supplier;
  final _lines = <LineDraft>[];

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _add() {
    final used = _lines.map((l) => l.supply.id).toSet();
    final free = widget.supplies.where((s) => s.active && !used.contains(s.id));
    if (free.isEmpty) return;
    final s = free.first;
    setState(
      () =>
          _lines.add(LineDraft(s, cost: (s.unitCost / 100).toStringAsFixed(2))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = widget.suppliers.where((s) => s.active).toList();
    final total = _lines.fold<int>(0, (sum, l) {
      final q = Qty.parse(l.qty.text);
      final c = Money.parse(l.cost.text);
      return q == null || c == null ? sum : sum + Qty.cost(q, c);
    });
    return ActionDialog(
      title: 'Nueva compra',
      validate: () => _form.currentState!.validate(),
      onSubmit: () =>
          ref.read(inventoryServiceProvider).createPurchase(_supplier, [
            for (final l in _lines)
              PurchaseLine(
                supplyId: l.supply.id,
                name: l.supply.name,
                qty: Qty.parse(l.qty.text)!,
                unitCost: Money.parse(l.cost.text)!,
              ),
          ], actorUid: actorUidOf(ref)),
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Supplier>(
              initialValue: _supplier,
              decoration: const InputDecoration(labelText: 'Proveedor'),
              items: [
                for (final s in suppliers)
                  DropdownMenuItem(value: s, child: Text(s.name)),
              ],
              onChanged: (s) => setState(() => _supplier = s),
              validator: (v) => v == null ? 'Elige un proveedor.' : null,
            ),
            const SizedBox(height: 8),
            for (final (i, l) in _lines.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Supply>(
                            initialValue: l.supply,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Insumo ${i + 1}',
                            ),
                            items: [
                              for (final s in widget.supplies.where(
                                (s) =>
                                    s.active &&
                                    (s.id == l.supply.id ||
                                        !_lines.any(
                                          (o) => o.supply.id == s.id,
                                        )),
                              ))
                                DropdownMenuItem(
                                  value: s,
                                  child: Text('${s.name} (${s.unit.label})'),
                                ),
                            ],
                            onChanged: (s) => setState(() => l.supply = s!),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setState(() => _lines.removeAt(i).dispose()),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: l.qty,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Cantidad (${l.supply.unit.label})',
                            ),
                            validator: Qty.validate,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: l.cost,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Costo por ${l.supply.unit.label} (S/)',
                            ),
                            validator: (v) =>
                                Money.validate(v, allowZero: true),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_lines.length < InventoryValidation.maxLines)
              TextButton.icon(
                icon: const Icon(Icons.add),
                onPressed: _add,
                label: const Text('Agregar insumo'),
              ),
            Text(
              'Total: S/ ${(total / 100).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class CancelPurchaseDialog extends ConsumerStatefulWidget {
  const CancelPurchaseDialog({super.key, required this.purchase});
  final Purchase purchase;
  @override
  ConsumerState<CancelPurchaseDialog> createState() =>
      _CancelPurchaseDialogState();
}

class _CancelPurchaseDialogState extends ConsumerState<CancelPurchaseDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ActionDialog(
    title: 'Cancelar compra',
    submitLabel: 'Cancelar compra',
    validate: () => _form.currentState!.validate(),
    onSubmit: () => ref
        .read(inventoryServiceProvider)
        .cancelPurchase(
          widget.purchase,
          _reason.text,
          actorUid: actorUidOf(ref),
        ),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _reason,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Motivo'),
        validator: InventoryValidation.reason,
      ),
    ),
  );
}

/// Receta de un plato: insumos y cantidad por porción, con el costo resultante.
class RecipeDialog extends ConsumerStatefulWidget {
  const RecipeDialog({
    super.key,
    required this.dishId,
    required this.dishName,
    required this.priceCents,
    required this.supplies,
    this.recipe,
  });
  final String dishId;
  final String dishName;
  final int priceCents;
  final List<Supply> supplies;
  final Recipe? recipe;
  @override
  ConsumerState<RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends ConsumerState<RecipeDialog> {
  final _form = GlobalKey<FormState>();
  late final List<LineDraft> _lines = [
    for (final i in widget.recipe?.ingredients ?? const <RecipeIngredient>[])
      if (widget.supplies.any((s) => s.id == i.supplyId))
        LineDraft(
          widget.supplies.firstWhere((s) => s.id == i.supplyId),
          qty: Qty.format(i.qty),
        ),
  ];

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _add() {
    final used = _lines.map((l) => l.supply.id).toSet();
    final free = widget.supplies.where((s) => s.active && !used.contains(s.id));
    if (free.isNotEmpty) setState(() => _lines.add(LineDraft(free.first)));
  }

  @override
  Widget build(BuildContext context) {
    final cost = _lines.fold<int>(0, (sum, l) {
      final q = Qty.parse(l.qty.text);
      return q == null ? sum : sum + Qty.cost(q, l.supply.unitCost);
    });
    final margin = widget.priceCents - cost;
    return ActionDialog(
      title: 'Receta · ${widget.dishName}',
      validate: () => _form.currentState!.validate(),
      onSubmit: () =>
          ref.read(inventoryServiceProvider).saveRecipe(widget.dishId, [
            for (final l in _lines)
              RecipeIngredient(
                supplyId: l.supply.id,
                name: l.supply.name,
                qty: Qty.parse(l.qty.text)!,
              ),
          ], actorUid: actorUidOf(ref)),
      content: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cantidad de cada insumo por porción.'),
            for (final (i, l) in _lines.indexed)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<Supply>(
                      initialValue: l.supply,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Insumo'),
                      items: [
                        for (final s in widget.supplies.where(
                          (s) =>
                              s.active &&
                              (s.id == l.supply.id ||
                                  !_lines.any((o) => o.supply.id == s.id)),
                        ))
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.name} (${s.unit.label})'),
                          ),
                      ],
                      onChanged: (s) => setState(() => l.supply = s!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: l.qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cant. (${l.supply.unit.label})',
                      ),
                      validator: Qty.validate,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        setState(() => _lines.removeAt(i).dispose()),
                  ),
                ],
              ),
            if (_lines.length < InventoryValidation.maxIngredients)
              TextButton.icon(
                icon: const Icon(Icons.add),
                onPressed: _add,
                label: const Text('Agregar insumo'),
              ),
            const Divider(),
            Text('Costo por porción: S/ ${(cost / 100).toStringAsFixed(2)}'),
            Text(
              'Precio de venta: S/ ${(widget.priceCents / 100).toStringAsFixed(2)}',
            ),
            Text(
              'Margen: S/ ${(margin / 100).toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: margin < 0 ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
