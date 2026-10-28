import 'package:flutter/material.dart';

import '../../../core/error/error_mapper.dart';

class OperationButton extends StatefulWidget {
  const OperationButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final Future<void> Function()? onPressed;
  @override
  State<OperationButton> createState() => _OperationButtonState();
}

class _OperationButtonState extends State<OperationButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _busy || widget.onPressed == null
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.onPressed!();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ErrorMapper.map(e).message)),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    child: Text(_busy ? 'Guardando…' : widget.label),
  );
}
