import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../models/restaurant_table.dart';
import 'table_repository.dart';

class FirestoreTableRepository implements TableRepository {
  FirestoreTableRepository(this._db);
  final FirebaseFirestore _db;
  @override
  Stream<List<RestaurantTable>> watchTables() => _db
      .collection(FirestorePaths.mesas)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => RestaurantTable.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id))),
      );
  @override
  Future<void> saveTable(
    String number,
    int capacity,
    bool active, {
    required bool create,
  }) => _db.runTransaction((tx) async {
    final ref = _db.collection(FirestorePaths.mesas).doc(number);
    final snapshot = await tx.get(ref);
    if (create && snapshot.exists) {
      throw const AppFailure('Ya existe una mesa con ese número.');
    }
    if (!create && !snapshot.exists) {
      throw const AppFailure('La mesa ya no existe.');
    }
    final current = snapshot.data();
    if (!active && current?['pedidoActivo'] != null) {
      throw const AppFailure(
        'No puedes desactivar una mesa con pedido activo.',
      );
    }
    tx.set(ref, {
      'numero': number,
      'capacidad': capacity,
      'activo': active,
      'pedidoActivo': current?['pedidoActivo'],
    });
  });
}
