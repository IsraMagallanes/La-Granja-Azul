import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../../inventory/models/inventory_models.dart';
import '../../inventory/services/consumption_planner.dart';
import '../models/order_item.dart';
import '../models/restaurant_order.dart';
import 'order_repository.dart';

class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._db);
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection(FirestorePaths.pedidos);
  @override
  Stream<List<RestaurantOrder>> watchOrders({String? waiterId}) {
    final Query<Map<String, dynamic>> query = waiterId == null
        ? _orders
        : _orders.where('meseroId', isEqualTo: waiterId);
    return query.snapshots().map(
      (s) => s.docs.map((d) => RestaurantOrder.fromMap(d.id, d.data())).toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        ),
    );
  }

  @override
  Stream<RestaurantOrder?> watchOrder(String id) => _orders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? RestaurantOrder.fromMap(d.id, d.data()!) : null);
  @override
  Stream<List<OrderItem>> watchItems(String orderId) => _orders
      .doc(orderId)
      .collection('detalles')
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => OrderItem.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );
  @override
  Future<String> openOrder(String tableId, String waiterId) async {
    final order = _orders.doc();
    final table = _db.collection(FirestorePaths.mesas).doc(tableId);
    await _db.runTransaction((tx) async {
      final waiter = (await tx.get(
        _db.collection(FirestorePaths.usuarios).doc(waiterId),
      )).data();
      if (waiter == null) {
        throw const AppFailure('No se encontró el perfil responsable.');
      }
      final data = (await tx.get(table)).data();
      if (data == null || data['activo'] != true) {
        throw const AppFailure('La mesa no está activa.');
      }
      if (data['pedidoActivo'] != null) {
        throw const AppFailure('Otro pedido ya ocupa esta mesa.');
      }
      tx.set(order, {
        'mesaId': tableId,
        'meseroId': waiterId,
        'meseroNombre': waiter['nombre'],
        'estado': 'abierto',
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'revision': 0,
        'cantidadDetalles': 0,
        'detalleModificado': '',
      });
      tx.update(table, {'pedidoActivo': order.id});
    });
    return order.id;
  }

  Future<void> _item(
    String orderId,
    String dishId, {
    int? quantity,
    String notes = '',
    bool create = false,
  }) => _db.runTransaction((tx) async {
    final orderRef = _orders.doc(orderId);
    final order = (await tx.get(orderRef)).data();
    if (order == null || order['estado'] != 'abierto') {
      throw const AppFailure('El pedido ya no es editable.');
    }
    final itemRef = orderRef.collection('detalles').doc(dishId);
    final existing = (await tx.get(itemRef)).data();
    Map<String, dynamic>? data;
    if (create) {
      if ((order['cantidadDetalles'] as int) >= 50) {
        throw const AppFailure('Máximo 50 platos diferentes por pedido.');
      }
      if (existing != null) {
        throw const AppFailure('El plato ya está agregado. Edita su cantidad.');
      }
      final dish = (await tx.get(
        _db.collection(FirestorePaths.carta).doc(dishId),
      )).data();
      if (dish == null || dish['disponible'] != true) {
        throw const AppFailure('El plato ya no está disponible.');
      }
      final category = (await tx.get(
        _db
            .collection(FirestorePaths.categorias)
            .doc(dish['categoriaId'] as String),
      )).data();
      if (category?['activo'] != true) {
        throw const AppFailure('La categoría ya no está activa.');
      }
      data = {
        'nombre': dish['nombre'],
        'precio': dish['precio'],
        'cantidad': quantity,
        'observaciones': notes,
      };
    } else {
      if (existing == null) {
        throw const AppFailure('El producto ya fue retirado.');
      }
      if (quantity != null) {
        data = {...existing, 'cantidad': quantity, 'observaciones': notes};
      }
    }
    if (data == null) {
      tx.delete(itemRef);
    } else {
      tx.set(itemRef, data);
    }
    tx.update(orderRef, {
      'revision': (order['revision'] as int) + 1,
      'cantidadDetalles':
          (order['cantidadDetalles'] as int) +
          (create ? 1 : (quantity == null ? -1 : 0)),
      'detalleModificado': dishId,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  });
  @override
  Future<void> addItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  ) => _item(orderId, dishId, quantity: quantity, notes: notes, create: true);
  @override
  Future<void> updateItem(
    String orderId,
    String dishId,
    int quantity,
    String notes,
  ) => _item(orderId, dishId, quantity: quantity, notes: notes);
  @override
  Future<void> removeItem(String orderId, String dishId) =>
      _item(orderId, dishId);
  @override
  Future<void> changeStatus(String orderId, OrderStatus status) {
    if (status != OrderStatus.registrado) {
      throw const AppFailure('Transición de estado no válida.');
    }
    return _close(orderId, status);
  }

  @override
  Future<void> cancelOrder(String orderId, String reason, String actorUid) =>
      _close(
        orderId,
        OrderStatus.cancelado,
        reason: reason,
        actorUid: actorUid,
      );

  @override
  Future<void> advanceKitchen(
    String orderId,
    KitchenStatus to,
    String actorUid, {
    String? forceReason,
  }) async {
    // Los platos de un pedido registrado ya no cambian (las reglas lo impiden),
    // así que se leen fuera de la transacción; recetas e insumos, dentro.
    final portions = <String, int>{};
    if (to == KitchenStatus.listo) {
      final items = await _orders.doc(orderId).collection('detalles').get();
      for (final d in items.docs) {
        portions[d.id] = d.data()['cantidad'] as int;
      }
    }
    return _db.runTransaction((tx) async {
      final ref = _orders.doc(orderId);
      final order = (await tx.get(ref)).data();
      if (order == null || order['estado'] != 'registrado') {
        throw const AppFailure('El pedido no está en la cocina.');
      }
      final from = KitchenStatus.values.byName(
        (order['estadoCocina'] as String?) ?? 'pendiente',
      );
      if (from.next != to) {
        throw AppFailure(
          'Otro usuario ya lo movió: ahora está «${from.label}». Se actualizará.',
        );
      }
      if (to == KitchenStatus.listo) {
        await _deductInventory(tx, orderId, portions, actorUid, forceReason);
      }
      tx.update(ref, {
        'estadoCocina': to.name,
        'revision': (order['revision'] as int) + 1,
        'actualizadoEn': FieldValue.serverTimestamp(),
        ...switch (to) {
          KitchenStatus.preparando => {
            'preparandoEn': FieldValue.serverTimestamp(),
            'cocinaPor': actorUid,
          },
          KitchenStatus.listo => {'listoEn': FieldValue.serverTimestamp()},
          KitchenStatus.entregado => {
            'entregadoEn': FieldValue.serverTimestamp(),
          },
          KitchenStatus.pendiente => const <String, dynamic>{},
        },
      });
    });
  }

  /// Fase 8B: descuenta del inventario lo que consume el pedido (receta × cantidad)
  /// dentro de la misma transacción que lo pasa a «Listo». Deja un documento de
  /// descuento con el id del pedido (de solo creación: un único descuento) y un
  /// movimiento «consumo» por insumo. Lanza si falta stock: no cambia nada.
  Future<void> _deductInventory(
    Transaction tx,
    String orderId,
    Map<String, int> portions,
    String actorUid,
    String? forceReason,
  ) async {
    final recipes = <String, Recipe?>{};
    for (final dish in portions.keys) {
      final data = (await tx.get(
        _db.collection(FirestorePaths.recetas).doc(dish),
      )).data();
      recipes[dish] = data == null ? null : Recipe.fromMap(dish, data);
    }
    final needs = ConsumptionPlanner.needs(portions, recipes);
    final supplies = <String, Supply?>{};
    for (final id in needs.keys) {
      final data = (await tx.get(
        _db.collection(FirestorePaths.insumos).doc(id),
      )).data();
      supplies[id] = data == null ? null : Supply.fromMap(id, data);
    }
    final profile = (await tx.get(
      _db.collection(FirestorePaths.usuarios).doc(actorUid),
    )).data();
    if (profile == null) throw const AppFailure('No se encontró tu perfil.');
    final name = profile['nombre'] as String;
    final plan = ConsumptionPlanner.plan(
      needs: needs,
      supplies: supplies,
      dishesWithoutRecipe: ConsumptionPlanner.dishesWithoutRecipe(
        portions,
        recipes,
      ),
      // Con motivo (solo Admin/Superadmin; las reglas lo exigen) se descuenta lo
      // disponible en vez de rechazar.
      allowShortage: forceReason != null,
    );
    final forced = plan.shortages.isNotEmpty;
    final marker = _db
        .collection(FirestorePaths.descuentosInventario)
        .doc(orderId);
    if ((await tx.get(marker)).exists) {
      throw const AppFailure('Este pedido ya descontó su inventario.');
    }
    tx.set(marker, {
      'insumos': plan.lines.length,
      'platosSinReceta': plan.dishesWithoutRecipe,
      'insumosOmitidos': plan.skippedSupplies,
      if (forced) 'forzado': true,
      'creadoPor': actorUid,
      'creadoPorNombre': name,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    if (forced) {
      // Auditoría independiente de la excepción: motivo, faltantes, quién y cuándo.
      tx.set(
        _db.collection(FirestorePaths.excepcionesInventario).doc(orderId),
        {
          'motivo': forceReason,
          'faltantes': [for (final s in plan.shortages) s.toMap()],
          'creadoPor': actorUid,
          'creadoPorNombre': name,
          'creadoEn': FieldValue.serverTimestamp(),
        },
      );
    }
    for (var n = 0; n < plan.lines.length; n++) {
      final line = plan.lines[n];
      final move = _db
          .collection(FirestorePaths.movimientosInventario)
          .doc('${orderId}_$n');
      tx.set(move, {
        'insumoId': line.supply.id,
        'insumoNombre': line.supply.name,
        'tipo': MovementKind.consumo.name,
        'delta': -line.qty,
        'stockResultante': line.resulting,
        'motivo': '',
        'pedidoId': orderId,
        'linea': n,
        'creadoPor': actorUid,
        'creadoPorNombre': name,
        'creadoEn': FieldValue.serverTimestamp(),
      });
      tx.update(_db.collection(FirestorePaths.insumos).doc(line.supply.id), {
        'stock': line.resulting,
        'ultimoMovimiento': move.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _close(
    String orderId,
    OrderStatus status, {
    String? reason,
    String? actorUid,
  }) => _db.runTransaction((tx) async {
    final ref = _orders.doc(orderId);
    final order = (await tx.get(ref)).data();
    if (order == null || order['estado'] != 'abierto') {
      throw const AppFailure('El pedido ya no es editable.');
    }
    if (status == OrderStatus.registrado && order['cantidadDetalles'] == 0) {
      throw const AppFailure('Agrega al menos un plato antes de registrar.');
    }
    final tableRef = _db
        .collection(FirestorePaths.mesas)
        .doc(order['mesaId'] as String);
    final table = (await tx.get(tableRef)).data();
    if (table?['pedidoActivo'] != orderId) {
      throw const AppFailure('La mesa no está vinculada a este pedido.');
    }
    tx.update(ref, {
      'estado': status.name,
      'revision': (order['revision'] as int) + 1,
      'actualizadoEn': FieldValue.serverTimestamp(),
      if (status == OrderStatus.registrado) ...{
        'estadoCocina': KitchenStatus.pendiente.name,
        'registradoEn': FieldValue.serverTimestamp(),
      },
      if (status == OrderStatus.cancelado) ...{
        'motivoCancelacion': reason,
        'canceladoPor': actorUid,
      },
    });
    if (status == OrderStatus.cancelado) {
      tx.update(tableRef, {'pedidoActivo': null});
    }
  });
}
