import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../models/restaurant_table.dart';
import '../controllers/table_providers.dart';
import '../services/table_service.dart';

class TableEditor extends ConsumerStatefulWidget {
  const TableEditor({super.key, this.table});
  final RestaurantTable? table;
  @override
  ConsumerState<TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends ConsumerState<TableEditor> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.table?.id ?? '');
  late final _capacity = TextEditingController(
    text: widget.table?.capacity.toString() ?? '',
  );
  late bool _active = widget.table?.active ?? true;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _number.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(tableServiceProvider)
          .save(
            _number.text.trim(),
            int.parse(_capacity.text),
            _active,
            create: widget.table == null,
          );
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
      title: Text(widget.table == null ? 'Nueva mesa' : 'Editar mesa'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _number,
                  enabled: widget.table == null,
                  decoration: const InputDecoration(
                    labelText: 'Número único de mesa',
                  ),
                  keyboardType: TextInputType.number,
                  validator: TableValidation.number,
                ),
                TextFormField(
                  controller: _capacity,
                  decoration: const InputDecoration(labelText: 'Capacidad'),
                  keyboardType: TextInputType.number,
                  validator: TableValidation.capacity,
                ),
                SwitchListTile(
                  title: const Text('Mesa activa'),
                  value: _active,
                  onChanged: widget.table?.occupied == true
                      ? null
                      : (v) => setState(() => _active = v),
                ),
                if (widget.table?.occupied == true)
                  const Text(
                    'No se puede desactivar mientras tenga un pedido activo.',
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
