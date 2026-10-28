import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../controllers/menu_providers.dart';
import '../models/dish.dart';
import '../models/menu_category.dart';
import '../services/menu_service.dart';
import 'dish_image.dart';

/// Un solo formulario por diálogo; mantiene el borrador y el estado de guardado.
class MenuEditor extends ConsumerStatefulWidget {
  const MenuEditor.category({super.key, this.category})
    : isDish = false,
      dish = null,
      categories = const [];
  const MenuEditor.dish({super.key, this.dish, required this.categories})
    : isDish = true,
      category = null;
  final bool isDish;
  final MenuCategory? category;
  final Dish? dish;
  final List<MenuCategory> categories;
  @override
  ConsumerState<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends ConsumerState<MenuEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.dish?.name ?? widget.category?.name ?? '',
  );
  late final _description = TextEditingController(
    text: widget.dish?.description ?? '',
  );
  late final _price = TextEditingController(
    text: widget.dish?.price.toStringAsFixed(2) ?? '',
  );
  late final _image = TextEditingController(text: widget.dish?.imageUrl ?? '');
  late String? _categoryId = widget.dish?.categoryId;
  late bool _enabled =
      widget.dish?.available ?? widget.category?.active ?? true;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in [_name, _description, _price, _image]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = ref.read(menuServiceProvider);
      if (widget.isDish) {
        await service.saveDish(
          Dish(
            id: widget.dish?.id ?? '',
            name: _name.text,
            description: _description.text,
            categoryId: _categoryId!,
            price: MenuValidation.parsePrice(_price.text)!,
            imageUrl: _image.text,
            available: _enabled,
          ),
        );
      } else {
        await service.saveCategory(
          MenuCategory(
            id: widget.category?.id ?? '',
            name: _name.text,
            active: _enabled,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = ErrorMapper.map(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories
        .where((c) => c.active || c.id == _categoryId)
        .toList();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.isDish ? 'Editar plato' : 'Editar categoría'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => MenuValidation.requiredText(v),
                  ),
                  if (widget.isDish) ...[
                    TextFormField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                      ),
                      validator: (v) =>
                          MenuValidation.requiredText(v, max: 2000),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: categories.any((c) => c.id == _categoryId)
                          ? _categoryId
                          : null,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: [
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(
                              '${category.name}${category.active ? '' : ' (inactiva)'}',
                            ),
                          ),
                      ],
                      onChanged: (v) => _categoryId = v,
                      validator: (v) =>
                          v == null ? 'Selecciona una categoría.' : null,
                    ),
                    TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(
                        labelText: 'Precio (S/)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: MenuValidation.price,
                    ),
                    TextFormField(
                      controller: _image,
                      decoration: const InputDecoration(
                        labelText: 'URL HTTPS de la imagen',
                      ),
                      validator: MenuValidation.imageUrl,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (MenuValidation.imageUrl(_image.text) == null)
                      DishImage(url: _image.text.trim()),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.isDish ? 'Disponible' : 'Categoría activa',
                    ),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  if (!widget.isDish)
                    const Text(
                      'Al desactivar la categoría se ocultan todos sus platos de la carta pública. Los platos conservan su categoría y reaparecen al reactivarla.',
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando...' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
