import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../controllers/menu_providers.dart';
import '../models/dish.dart';
import '../models/menu_category.dart';
import '../services/dish_photo_compressor.dart';
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
  bool _processingPhoto = false;
  String? _error;

  /// Id del plato; un plato nuevo lo recibe aquí para poder guardar su foto.
  late final String _dishId = widget.dish?.id ?? MenuService.newDishId();

  /// Foto elegida (ya reducida) que se guardará con el plato.
  Uint8List? _newPhoto;
  bool _removePhoto = false;
  @override
  void dispose() {
    for (final controller in [_name, _description, _price, _image]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _processingPhoto = true;
      _error = null;
    });
    try {
      final original = await ref.read(dishPhotoPickerProvider).pick();
      if (original == null) return;
      // Deja pintar el indicador antes de la parte pesada de la reducción.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final jpeg = DishPhotoCompressor.fit(original);
      if (mounted) {
        setState(() {
          _newPhoto = jpeg;
          _removePhoto = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = ErrorMapper.map(error).message);
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
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
            id: _dishId,
            name: _name.text,
            description: _description.text,
            categoryId: _categoryId!,
            price: MenuValidation.parsePrice(_price.text)!,
            imageUrl: _image.text,
            available: _enabled,
          ),
        );
        // La foto va después: sus reglas exigen que el plato ya exista. Si
        // falla, el plato quedó guardado y «Guardar» reintenta solo la foto.
        final photos = ref.read(dishPhotoRepositoryProvider);
        if (_newPhoto != null) {
          await photos.save(_dishId, _newPhoto!);
          ref.invalidate(dishPhotoProvider(_dishId));
        } else if (_removePhoto) {
          await photos.remove(_dishId);
          ref.invalidate(dishPhotoProvider(_dishId));
        }
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

  /// ¿Tiene el plato una foto (guardada o recién elegida) que se pueda quitar?
  bool get _hasPhoto {
    if (_newPhoto != null) return true;
    final id = widget.dish?.id;
    if (_removePhoto || id == null) return false;
    return ref.watch(dishPhotoProvider(id)).value != null;
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
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DishImage(
                        dishId: _removePhoto ? null : widget.dish?.id,
                        bytes: _newPhoto,
                        url:
                            MenuValidation.optionalImageUrl(_image.text) == null
                            ? _image.text.trim()
                            : '',
                        height: 160,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving || _processingPhoto
                              ? null
                              : _pickPhoto,
                          icon: _processingPhoto
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            _processingPhoto
                                ? 'Procesando...'
                                : _hasPhoto
                                ? 'Cambiar foto'
                                : 'Elegir foto',
                          ),
                        ),
                        if (_hasPhoto)
                          TextButton.icon(
                            onPressed: _saving || _processingPhoto
                                ? null
                                : () => setState(() {
                                    _newPhoto = null;
                                    _removePhoto = true;
                                  }),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Quitar foto'),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'La foto se reduce automáticamente (máx. 100 KB). '
                        'Si no hay foto se usa la URL, si la hay.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextFormField(
                      controller: _image,
                      decoration: const InputDecoration(
                        labelText: 'URL HTTPS de la imagen (opcional)',
                      ),
                      validator: MenuValidation.optionalImageUrl,
                      onChanged: (_) => setState(() {}),
                    ),
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
