import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../controllers/menu_providers.dart';

/// Fotografía de un plato; llena el espacio disponible. Prioridad: [bytes]
/// (foto aún sin guardar), la foto guardada del plato ([dishId]) y por último
/// la [url]. Sin ninguna, o si no carga, muestra un marcador sobrio.
class DishImage extends ConsumerWidget {
  const DishImage({
    super.key,
    this.dishId,
    this.url = '',
    this.bytes,
    this.height,
  });

  final String? dishId;
  final String url;
  final Uint8List? bytes;
  final double? height;

  static const _placeholder = ColoredBox(
    color: AppColors.blueSoft,
    child: Center(
      child: Icon(
        Icons.restaurant,
        semanticLabel: 'Imagen no disponible',
        size: 40,
        color: AppColors.blue,
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = dishId;
    final stored = bytes == null && id != null && id.isNotEmpty
        ? ref.watch(dishPhotoProvider(id))
        : null;
    final photo = bytes ?? stored?.value;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: photo != null
          ? Image.memory(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder,
            )
          : stored?.isLoading == true
          ? const Center(child: CircularProgressIndicator())
          : _fromUrl(),
    );
  }

  Widget _fromUrl() => url.trim().isEmpty
      ? _placeholder
      : Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, _, _) => _placeholder,
        );
}
