import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/lima_time.dart';
import '../../orders/controllers/order_providers.dart';
import '../models/cash_models.dart';
import '../repositories/cash_repository.dart';
import '../services/cash_service.dart';

final cashRepositoryProvider = Provider<CashRepository>(
  (ref) => throw UnimplementedError('cashRepositoryProvider sin override'),
);
final cashServiceProvider = Provider<CashService>(
  (ref) => CashService(
    ref.watch(cashRepositoryProvider),
    ref.watch(orderRepositoryProvider),
  ),
);

/// La caja abierta ahora (null = no hay).
final openBoxProvider = StreamProvider.autoDispose<CashBox?>(
  (ref) => ref.watch(cashRepositoryProvider).watchOpenBox(),
  retry: (_, _) => null,
);
final boxesProvider = StreamProvider.autoDispose<List<CashBox>>(
  (ref) => ref.watch(cashRepositoryProvider).watchBoxes(),
  retry: (_, _) => null,
);
final boxPaymentsProvider = StreamProvider.autoDispose
    .family<List<Payment>, String>(
      (ref, boxId) =>
          ref.watch(cashRepositoryProvider).watchPayments(boxId: boxId),
      retry: (_, _) => null,
    );
final boxMovementsProvider = StreamProvider.autoDispose
    .family<List<CashMovement>, String>(
      (ref, boxId) => ref.watch(cashRepositoryProvider).watchMovements(boxId),
      retry: (_, _) => null,
    );

/// Ventas desde las 00:00 de hoy (hora de Lima).
final todayPaymentsProvider = StreamProvider.autoDispose<List<Payment>>(
  (ref) => ref
      .watch(cashRepositoryProvider)
      .watchPayments(since: LimaTime.startOfDay(DateTime.now())),
  retry: (_, _) => null,
);
final allPaymentsProvider = StreamProvider.autoDispose<List<Payment>>(
  (ref) => ref.watch(cashRepositoryProvider).watchPayments(),
  retry: (_, _) => null,
);
