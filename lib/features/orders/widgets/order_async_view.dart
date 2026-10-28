import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';

class OrderAsyncView<T> extends StatelessWidget {
  const OrderAsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
  });
  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ErrorMapper.map(e).message),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
    data: builder,
  );
}
