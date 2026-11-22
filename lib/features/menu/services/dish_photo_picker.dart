import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Elige una foto del dispositivo (galería en Android, selector de archivos en
/// la web). Interfaz propia para poder sustituirla en las pruebas.
abstract interface class DishPhotoPicker {
  /// Bytes de la foto elegida, o `null` si se canceló.
  Future<Uint8List?> pick();
}

class ImagePickerDishPhotoPicker implements DishPhotoPicker {
  ImagePickerDishPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick() async {
    // El tamaño se reduce de entrada para que decodificar no sea lento.
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return file?.readAsBytes();
  }
}
