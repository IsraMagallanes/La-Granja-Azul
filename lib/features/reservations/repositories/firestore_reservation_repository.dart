import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/firestore_paths.dart';
import '../models/reservation.dart';
import 'reservation_repository.dart';

class FirestoreReservationRepository implements ReservationRepository {
  FirestoreReservationRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.reservaciones);

  Map<String, dynamic> _fields(ReservationDraft d) => {
    'mesaId': d.tableId,
    'cliente': d.customer,
    'telefono': d.phone,
    'personas': d.partySize,
    'fechaHora': Timestamp.fromDate(d.at),
    'notas': d.notes,
  };

  @override
  Stream<List<Reservation>> watchReservations() => _col.snapshots().map(
    (s) =>
        [for (final d in s.docs) Reservation.fromMap(d.id, d.data())]
          ..sort((a, b) => a.at.compareTo(b.at)),
  );

  @override
  Future<void> create(
    ReservationDraft draft, {
    required String actorUid,
    required String actorName,
  }) => _col.add({
    ..._fields(draft),
    'estado': 'pendiente',
    'creadoPor': actorUid,
    'creadoPorNombre': actorName,
    'creadoEn': FieldValue.serverTimestamp(),
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> edit(
    String id,
    ReservationDraft draft, {
    required bool confirmed,
  }) => _col.doc(id).update({
    ..._fields(draft),
    'estado': confirmed ? 'confirmada' : 'pendiente',
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  Future<void> _change(String id, Map<String, dynamic> fields) => _col
      .doc(id)
      .update({...fields, 'actualizadoEn': FieldValue.serverTimestamp()});

  @override
  Future<void> confirm(String id) => _change(id, {'estado': 'confirmada'});
  @override
  Future<void> cancel(String id, String reason) =>
      _change(id, {'estado': 'cancelada', 'motivoCancelacion': reason});
  @override
  Future<void> markNoShow(String id) => _change(id, {'estado': 'noAsistio'});
  @override
  Future<void> seat(String id, String orderId) =>
      _change(id, {'estado': 'cumplida', 'pedidoId': orderId});
}
