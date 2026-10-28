import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/restaurant_table.dart';
import '../repositories/table_repository.dart';
import '../services/table_service.dart';

final tableRepositoryProvider = Provider<TableRepository>(
  (ref) => throw UnimplementedError('tableRepositoryProvider sin override'),
);
final tableServiceProvider = Provider<TableService>(
  (ref) => TableService(ref.watch(tableRepositoryProvider)),
);
final tablesProvider = StreamProvider.autoDispose<List<RestaurantTable>>(
  (ref) => ref.watch(tableRepositoryProvider).watchTables(),
  retry: (_, _) => null,
);
