import 'package:flutter/material.dart';

class DishImage extends StatelessWidget {
  const DishImage({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 160,
    width: double.infinity,
    child: Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, _, _) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          semanticLabel: 'Imagen no disponible',
          size: 48,
        ),
      ),
    ),
  );
}
