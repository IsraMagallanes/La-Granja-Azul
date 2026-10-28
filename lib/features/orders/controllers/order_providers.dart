import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/controllers/auth_providers.dart';
import '../../auth/models/session_state.dart';
import '../../roles/models/user_role.dart';
import '../models/restaurant_order.dart';
import '../models/order_item.dart';
import '../repositories/order_repository.dart';
import '../services/order_service.dart';

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => throw UnimplementedError('orderRepositoryProvider sin override'),
);
final orderServiceProvider = Provider<OrderService>(
  (ref) => OrderService(ref.watch(orderRepositoryProvider)),
);
final ordersProvider = StreamProvider.autoDispose<List<RestaurantOrder>>((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session is! Authenticated) return Stream.value([]);
  return ref
      .watch(orderRepositoryProvider)
      .watchOrders(
        waiterId: session.user.role == UserRole.mesero
            ? session.user.uid
            : null,
      );
}, retry: (_, _) => null);
final orderProvider = StreamProvider.autoDispose
    .family<RestaurantOrder?, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchOrder(id),
      retry: (_, _) => null,
    );
final orderItemsProvider = StreamProvider.autoDispose
    .family<List<OrderItem>, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchItems(id),
      retry: (_, _) => null,
    );
