import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../menu/controllers/menu_providers.dart';
import '../controllers/order_providers.dart';
import '../models/order_item.dart';
import '../services/order_service.dart';
import 'order_async_view.dart';

class ItemEditor extends ConsumerStatefulWidget {
  const ItemEditor({super.key, required this.orderId, this.item});
  final String orderId;
  final OrderItem? item;
  @override
  ConsumerState<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<ItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
    text: '${widget.item?.quantity ?? 1}',
  );
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  String? _dish;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (widget.item == null && _dish == null) {
      setState(() => _error = 'Selecciona un plato disponible.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(orderServiceProvider);
      if (widget.item == null) {
        await service.add(
          widget.orderId,
          _dish!,
          int.parse(_quantity.text),
          _notes.text,
        );
      } else {
        await service.update(
          widget.orderId,
          widget.item!.dishId,
          int.parse(_quantity.text),
          _notes.text,
        );
      }
      if (mounted) Navigator.pop(context);
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
      title: Text(widget.item?.name ?? 'Añadir plato'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.item == null)
                  OrderAsyncView(
                    value: ref.watch(menuCatalogProvider),
                    onRetry: () => ref.invalidate(menuCatalogProvider),
                    builder: (catalog) {
                      final active = catalog.categories
                          .where((c) => c.active)
                          .map((c) => c.id)
                          .toSet();
                      final dishes = catalog.dishes
                          .where(
                            (d) => d.available && active.contains(d.categoryId),
                          )
                          .toList();
                      return Column(
                        children: [
                          if (dishes.isEmpty)
                            const Text(
                              'No hay platos disponibles en categorías activas.',
                            ),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Plato',
                            ),
                            items: [
                              for (final d in dishes)
                                DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${d.name} · S/ ${d.price.toStringAsFixed(2)}',
                                  ),
                                ),
                            ],
                            onChanged: (v) => _dish = v,
                            validator: (v) =>
                                v == null || !dishes.any((d) => d.id == v)
                                ? 'Selecciona un plato disponible.'
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  validator: OrderValidation.quantity,
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                  ),
                  validator: OrderValidation.notes,
                ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}
