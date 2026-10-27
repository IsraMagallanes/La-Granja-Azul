import 'package:flutter/material.dart';

/// Muestra un diálogo de progreso que no se puede cerrar mientras dura [task]
/// y lo cierra al terminar, con éxito o con error (el error se propaga).
Future<T> runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 28, height: 28, child: CircularProgressIndicator()),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }
}
