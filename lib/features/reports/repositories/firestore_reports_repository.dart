import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../cashier/models/cash_models.dart';
import '../../inventory/models/inventory_models.dart';
import '../../orders/models/order_item.dart';
import 'reports_repository.dart';

class FirestoreReportsRepository implements ReportsRepository {
  FirestoreReportsRepository(this._db);
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _range(
    String collection,
    String field,
    DateTime from,
    DateTime to,
  ) => _db
      .collection(collection)
      .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where(field, isLessThan: Timestamp.fromDate(to));

  @override
  Future<List<Payment>> payments(DateTime from, DateTime to) async {
    final s = await _range(FirestorePaths.pagos, 'creadoEn', from, to).get();
    return [for (final d in s.docs) Payment.fromMap(d.id, d.data())];
  }

  @override
  Future<List<OrderItem>> soldItems(List<String> orderIds) async {
    final items = <OrderItem>[];
    for (final id in orderIds) {
      final s = await _db
          .collection(FirestorePaths.pedidos)
          .doc(id)
          .collection('detalles')
          .get();
      items.addAll([for (final d in s.docs) OrderItem.fromMap(d.id, d.data())]);
    }
    return items;
  }

  @override
  Future<List<Purchase>> receivedPurchases(DateTime from, DateTime to) async {
    final s = await _range('compras', 'recibidoEn', from, to).get();
    return [
      for (final d in s.docs)
        if (d.data()['estado'] == 'recibida') Purchase.fromMap(d.id, d.data()),
    ];
  }

  @override
  Future<List<StockMovement>> stockMovements(DateTime from, DateTime to) async {
    final s = await _range('movimientosInventario', 'creadoEn', from, to).get();
    return [for (final d in s.docs) StockMovement.fromMap(d.id, d.data())];
  }
}
