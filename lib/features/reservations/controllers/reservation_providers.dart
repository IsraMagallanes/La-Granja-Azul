import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/controllers/order_providers.dart';
import '../models/reservation.dart';
import '../repositories/reservation_repository.dart';
import '../services/reservation_service.dart';

final reservationRepositoryProvider = Provider<ReservationRepository>(
  (ref) =>
      throw UnimplementedError('reservationRepositoryProvider sin override'),
);
final reservationServiceProvider = Provider<ReservationService>(
  (ref) => ReservationService(
    ref.watch(reservationRepositoryProvider),
    ref.watch(orderRepositoryProvider),
  ),
);
final reservationsProvider = StreamProvider.autoDispose<List<Reservation>>(
  (ref) => ref.watch(reservationRepositoryProvider).watchReservations(),
  retry: (_, _) => null,
);
