import '../models/restaurant_table.dart';

abstract interface class TableRepository {
  Stream<List<RestaurantTable>> watchTables();
  Future<void> saveTable(
    String number,
    int capacity,
    bool active, {
    required bool create,
  });
}
