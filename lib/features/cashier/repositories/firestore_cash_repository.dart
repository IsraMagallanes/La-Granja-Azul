import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../../../core/error/app_failure.dart';
import '../models/cash_models.dart';
import 'cash_repository.dart';

class FirestoreCashRepository implements CashRepository {
  FirestoreCashRepository(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _lock =>
      _db.collection(FirestorePaths.cajaActiva).doc('actual');
  CollectionReference<Map<String, dynamic>> get _boxes =>
      _db.collection(FirestorePaths.cajas);

  Future<String> _nameOf(Transaction tx, String uid) async {
    final profile = (await tx.get(
      _db.collection(FirestorePaths.usuarios).doc(uid),
    )).data();
    if (profile == null) {
      throw const AppFailure('No se encontró tu perfil.');
    }
    return profile['nombre'] as String;
  }

  @override
  Stream<CashBox?> watchOpenBox() => _lock.snapshots().map((s) {
    final d = s.data();
    if (d == null) return null;
    return CashBox.fromMap(d['cajaId'] as String, {...d, 'estado': 'abierta'});
  });

  @override
  Stream<List<CashBox>> watchBoxes() => _boxes
      .orderBy('abiertaEn', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => [for (final d in s.docs) CashBox.fromMap(d.id, d.data())]);

  @override
  Stream<List<Payment>> watchPayments({String? boxId, DateTime? since}) {
    Query<Map<String, dynamic>> query = _db.collection(FirestorePaths.pagos);
    if (boxId != null) query = query.where('cajaId', isEqualTo: boxId);
    if (since != null) {
      query = query.where(
        'creadoEn',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );
    }
    return query.snapshots().map(
      (s) => [for (final d in s.docs) Payment.fromMap(d.id, d.data())]
        ..sort(
          (a, b) => (b.at ?? DateTime(1970)).compareTo(a.at ?? DateTime(1970)),
        ),
    );
  }

  @override
  Stream<List<CashMovement>> watchMovements(String boxId) => _db
      .collection(FirestorePaths.movimientosCaja)
      .where('cajaId', isEqualTo: boxId)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) CashMovement.fromMap(d.id, d.data())]
          ..sort(
            (a, b) =>
                (b.at ?? DateTime(1970)).compareTo(a.at ?? DateTime(1970)),
          ),
      );

  @override
  Future<String> openBox(int initialCents, {required String actorUid}) async {
    final ref = _boxes.doc();
    await _db.runTransaction((tx) async {
      if ((await tx.get(_lock)).exists) {
        throw const AppFailure('Ya hay una caja abierta.');
      }
      final name = await _nameOf(tx, actorUid);
      tx.set(ref, {
        'estado': 'abierta',
        'montoInicial': initialCents,
        'abiertaPor': actorUid,
        'abiertaPorNombre': name,
        'abiertaEn': FieldValue.serverTimestamp(),
      });
      tx.set(_lock, {
        'cajaId': ref.id,
        'montoInicial': initialCents,
        'abiertaPor': actorUid,
        'abiertaPorNombre': name,
        'abiertaEn': FieldValue.serverTimestamp(),
      });
    });
    return ref.id;
  }

  @override
  Future<void> addMovement(
    String boxId,
    MovementType type,
    int cents,
    String concept, {
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    final lock = (await tx.get(_lock)).data();
    if (lock == null || lock['cajaId'] != boxId) {
      throw const AppFailure('La caja ya no está abierta.');
    }
    tx.set(_db.collection(FirestorePaths.movimientosCaja).doc(), {
      'cajaId': boxId,
      'tipo': type.name,
      'monto': cents,
      'concepto': concept,
      'creadoPor': actorUid,
      'creadoPorNombre': await _nameOf(tx, actorUid),
      'creadoEn': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> charge({
    required String orderId,
    required int totalCents,
    required PaymentMethod method,
    required int receivedCents,
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    final orderRef = _db.collection(FirestorePaths.pedidos).doc(orderId);
    final payRef = _db.collection(FirestorePaths.pagos).doc(orderId);
    final lock = (await tx.get(_lock)).data();
    if (lock == null) {
      throw const AppFailure('Abre la caja antes de cobrar.');
    }
    if ((await tx.get(payRef)).exists) {
      throw const AppFailure('Este pedido ya fue cobrado.');
    }
    final order = (await tx.get(orderRef)).data();
    if (order == null || order['estado'] != 'registrado') {
      throw const AppFailure('El pedido ya no está pendiente de cobro.');
    }
    if (order['estadoCocina'] != 'entregado') {
      throw const AppFailure('El pedido aún no fue entregado en la mesa.');
    }
    final tableRef = _db
        .collection(FirestorePaths.mesas)
        .doc(order['mesaId'] as String);
    if ((await tx.get(tableRef)).data()?['pedidoActivo'] != orderId) {
      throw const AppFailure('La mesa no está vinculada a este pedido.');
    }
    final name = await _nameOf(tx, actorUid);
    tx.set(payRef, {
      'pedidoId': orderId,
      'mesaId': order['mesaId'],
      'cajaId': lock['cajaId'],
      'total': totalCents,
      'metodo': method.name,
      'recibido': method.isCash ? receivedCents : totalCents,
      'vuelto': method.isCash ? receivedCents - totalCents : 0,
      'cobradoPor': actorUid,
      'cobradoPorNombre': name,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, {
      'estado': 'pagado',
      'revision': (order['revision'] as int) + 1,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
    tx.update(tableRef, {'pedidoActivo': null});
  });

  @override
  Future<void> closeBox(
    String boxId, {
    required int countedCents,
    required CashSummary summary,
    required String notes,
    required String actorUid,
  }) => _db.runTransaction((tx) async {
    final lock = (await tx.get(_lock)).data();
    if (lock == null || lock['cajaId'] != boxId) {
      throw const AppFailure('Esta caja ya fue cerrada.');
    }
    final boxRef = _boxes.doc(boxId);
    final expected = summary.expectedCash;
    tx.update(boxRef, {
      'estado': 'cerrada',
      'cerradaPor': actorUid,
      'cerradaPorNombre': await _nameOf(tx, actorUid),
      'cerradaEn': FieldValue.serverTimestamp(),
      'esperadoEfectivo': expected,
      'montoContado': countedCents,
      'diferencia': countedCents - expected,
      'ventasEfectivo': summary.cashSales,
      'ventasOtros': summary.otherSales,
      'ingresos': summary.income,
      'egresos': summary.expenses,
      'cantidadVentas': summary.salesCount,
      'notasCierre': notes,
    });
    tx.delete(_lock);
  });
}
