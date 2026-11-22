import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../models/inventory_models.dart';
import 'inventory_repository.dart';

class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository(this._db);
  final FirebaseFirestore _db;

  static const _supplies = 'insumos';
  static const _moves = 'movimientosInventario';
  static const _suppliers = 'proveedores';
  static const _purchases = 'compras';
  static const _recipes = 'recetas';

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection(name);

  Future<String> _nameOf(Transaction tx, String uid) async {
    final profile = (await tx.get(
      _db.collection(FirestorePaths.usuarios).doc(uid),
    )).data();
    if (profile == null) throw const AppFailure('No se encontró tu perfil.');
    return profile['nombre'] as String;
  }

  Stream<List<T>> _watch<T>(
    String name,
    T Function(String, Map<String, dynamic>) build,
  ) =>
      _col(name)
          .snapshots()
          .map((s) => [for (final d in s.docs) build(d.id, d.data())]);

  @override
  Stream<List<Supply>> watchSupplies() => _watch(_supplies, Supply.fromMap).map(
    (l) =>
        l..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );

  @override
  Stream<List<StockMovement>> watchMovements() => _col(_moves)
      .orderBy('creadoEn', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) StockMovement.fromMap(d.id, d.data())],
      );

  @override
  Stream<List<Supplier>> watchSuppliers() =>
      _watch(_suppliers, Supplier.fromMap).map(
        (l) => l
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
      );

  @override
  Stream<List<Purchase>> watchPurchases() => _col(_purchases)
      .orderBy('creadoEn', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => [for (final d in s.docs) Purchase.fromMap(d.id, d.data())]);

  @override
  Stream<List<Recipe>> watchRecipes() => _watch(_recipes, Recipe.fromMap);

  @override
  Future<void> createSupply(
    String name,
    SupplyUnit unit,
    int minStock,
    int unitCost,
  ) => _col(_supplies).add({
    'nombre': name,
    'unidad': unit.name,
    'stock': 0,
    'stockMinimo': minStock,
    'costoUnitario': unitCost,
    'activo': true,
    'creadoEn': FieldValue.serverTimestamp(),
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> editSupply(
    String id, {
    required String name,
    required int minStock,
    required int unitCost,
    required bool active,
  }) => _col(_supplies).doc(id).update({
    'nombre': name,
    'stockMinimo': minStock,
    'costoUnitario': unitCost,
    'activo': active,
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> moveStock(
    String supplyId,
    MovementKind kind,
    int delta,
    String reason, {
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    final ref = _col(_supplies).doc(supplyId);
    final supply = (await tx.get(ref)).data();
    if (supply == null) throw const AppFailure('El insumo ya no existe.');
    final result = (supply['stock'] as int) + delta;
    if (result < 0) {
      throw const AppFailure('No hay stock suficiente para esa salida.');
    }
    final move = _col(_moves).doc();
    tx.set(move, {
      'insumoId': supplyId,
      'insumoNombre': supply['nombre'],
      'tipo': kind.name,
      'delta': delta,
      'stockResultante': result,
      'motivo': reason,
      'creadoPor': actorUid,
      'creadoPorNombre': await _nameOf(tx, actorUid),
      'creadoEn': FieldValue.serverTimestamp(),
    });
    tx.update(ref, {
      'stock': result,
      'ultimoMovimiento': move.id,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> saveSupplier(
    String? id, {
    required String name,
    required String ruc,
    required String phone,
    required String contact,
    required bool active,
  }) async {
    final fields = {
      'nombre': name,
      'ruc': ruc,
      'telefono': phone,
      'contacto': contact,
      'activo': active,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      await _col(_suppliers)
          .add({...fields, 'creadoEn': FieldValue.serverTimestamp()});
    } else {
      // Las reglas validan el documento completo: se conserva `creadoEn`.
      await _db.runTransaction((tx) async {
        final ref = _col(_suppliers).doc(id);
        final current = (await tx.get(ref)).data();
        if (current == null)
          throw const AppFailure('El proveedor ya no existe.');
        tx.set(ref, {...fields, 'creadoEn': current['creadoEn']});
      });
    }
  }

  @override
  Future<void> createPurchase(
    Supplier supplier,
    List<PurchaseLine> lines, {
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    // Las reglas piden las líneas ordenadas por insumo (así no hay repetidos).
    final sorted = [...lines]..sort((a, b) => a.supplyId.compareTo(b.supplyId));
    tx.set(_col(_purchases).doc(), {
      'proveedorId': supplier.id,
      'proveedorNombre': supplier.name,
      'lineas': [for (final l in sorted) l.toMap()],
      'estado': 'pendiente',
      'creadoPor': actorUid,
      'creadoPorNombre': await _nameOf(tx, actorUid),
      'creadoEn': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> receivePurchase(String id, {required String actorUid}) =>
      _db.runTransaction((tx) async {
        final ref = _col(_purchases).doc(id);
        final data = (await tx.get(ref)).data();
        if (data == null || data['estado'] != 'pendiente') {
          throw const AppFailure('Esta compra ya no está pendiente.');
        }
        final purchase = Purchase.fromMap(id, data);
        if (purchase.invalidLines > 0) {
          throw const AppFailure(
            'La compra tiene líneas ilegibles y no se puede recibir.',
          );
        }
        final byId = <String, Map<String, dynamic>>{};
        for (final line in purchase.lines) {
          final supply = (await tx.get(_col(_supplies).doc(line.supplyId)))
              .data();
          if (supply == null) {
            throw AppFailure('El insumo «${line.name}» ya no existe.');
          }
          byId[line.supplyId] = supply;
        }
        final name = await _nameOf(tx, actorUid);
        // Cada línea genera su movimiento con id fijo (compra_n): las reglas lo
        // enlazan a esa línea y exigen que existan todos al recibir.
        for (var n = 0; n < purchase.lines.length; n++) {
          final line = purchase.lines[n];
          final move = _col(_moves).doc('${id}_$n');
          final result = (byId[line.supplyId]!['stock'] as int) + line.qty;
          tx.set(move, {
            'insumoId': line.supplyId,
            'insumoNombre': byId[line.supplyId]!['nombre'],
            'tipo': 'compra',
            'delta': line.qty,
            'stockResultante': result,
            'motivo': '',
            'compraId': id,
            'linea': n,
            'costoUnitario': line.unitCost,
            'creadoPor': actorUid,
            'creadoPorNombre': name,
            'creadoEn': FieldValue.serverTimestamp(),
          });
          tx.update(_col(_supplies).doc(line.supplyId), {
            'stock': result,
            'costoUnitario': line.unitCost,
            'ultimoMovimiento': move.id,
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
        }
        tx.update(ref, {
          'estado': 'recibida',
          'recibidoPor': actorUid,
          'recibidoPorNombre': name,
          'recibidoEn': FieldValue.serverTimestamp(),
        });
      });

  @override
  Future<void> cancelPurchase(
    String id,
    String reason, {
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    final ref = _col(_purchases).doc(id);
    if ((await tx.get(ref)).data()?['estado'] != 'pendiente') {
      throw const AppFailure('Esta compra ya no está pendiente.');
    }
    tx.update(ref, {
      'estado': 'cancelada',
      'canceladoPor': actorUid,
      'canceladoPorNombre': await _nameOf(tx, actorUid),
      'canceladoEn': FieldValue.serverTimestamp(),
      'motivoCancelacion': reason,
    });
  });

  @override
  Future<void> saveRecipe(
    String dishId,
    List<RecipeIngredient> ingredients, {
    required String actorUid,
  }) => _col(_recipes).doc(dishId).set({
    'ingredientes': [for (final i in ingredients) i.toMap()],
    'actualizadoPor': actorUid,
    'actualizadoEn': FieldValue.serverTimestamp(),
  });
}
