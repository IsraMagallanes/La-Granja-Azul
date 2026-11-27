import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/app_failure.dart';
import '../../audit/models/audit_entry.dart';
import '../../users/models/app_user.dart';
import '../models/utensil_models.dart';
import 'utensil_repository.dart';

class FirestoreUtensilRepository implements UtensilRepository {
  FirestoreUtensilRepository(this._db);
  final FirebaseFirestore _db;

  static const _utensils = 'utensilios';
  static const _assignments = 'asignacionesUtensilios';
  static const _moves = 'movimientosUtensilios';
  static const _costs = 'costosUtensilios';
  static const _audit = 'auditoria';
  static const _waiters = 'directorioMeseros';

  @override
  Stream<List<Utensil>> watchUtensils() => _db
      .collection(_utensils)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) ?Utensil.tryParse(d.id, d.data()),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  @override
  Stream<List<UtensilAssignment>> watchAssignments() => _db
      .collection(_assignments)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) ?UtensilAssignment.tryParse(d.data())],
      );

  @override
  Stream<List<UtensilMovement>> watchMovements() => _db
      .collection(_moves)
      .orderBy('creadoEn', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs) ?UtensilMovement.tryParse(d.id, d.data()),
        ],
      );

  @override
  Stream<List<WaiterRef>> watchWaiters() => _db
      .collection(_waiters)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (d.data()['nombre'] is String)
              WaiterRef(
                d.id,
                d.data()['nombre'] as String,
                active: d.data()['activo'] == true,
              ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  @override
  Future<int> syncWaiterDirectory(List<WaiterRef> staff) async {
    final current = {
      for (final d in (await _db.collection(_waiters).get()).docs)
        d.id: (d.data()['nombre'], d.data()['activo']),
    };
    final stale = [
      for (final w in staff)
        if (current[w.uid] != (w.name, w.active)) w,
    ];
    // Un lote por pocos meseros: cada escritura consulta el perfil en las reglas.
    for (var i = 0; i < stale.length; i += 8) {
      final batch = _db.batch();
      for (final w in stale.skip(i).take(8)) {
        batch.set(_db.collection(_waiters).doc(w.uid), {
          'nombre': w.name,
          'activo': w.active,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    return stale.length;
  }

  @override
  Stream<Map<String, int>> watchCosts() => _db
      .collection(_costs)
      .snapshots()
      .map(
        (s) => {
          for (final d in s.docs)
            if (d.data()['costoUnitario'] is int)
              d.id: d.data()['costoUnitario'] as int,
        },
      );

  @override
  Future<void> saveUtensil(
    AppUser actor, {
    String? id,
    required String name,
    required int minStock,
    required bool active,
    int? newUnitCost,
  }) => _db.runTransaction((tx) async {
    final ref = _db.collection(_utensils).doc(id);
    final auditRef = _db.collection(_audit).doc();
    final current = id == null ? null : (await tx.get(ref)).data();
    if (id != null && current == null) {
      throw const AppFailure('El utensilio ya no existe.');
    }
    final changed = <String>[];
    if (current == null || current['nombre'] != name) changed.add('nombre');
    if (current == null || current['stockMinimo'] != minStock) {
      changed.add('stockMinimo');
    }
    if (current != null && current['activo'] != active) changed.add('activo');
    var version = (current?['versionCosto'] as int?) ?? 0;
    // Al crear, un costo 0 no genera versión (= sin costo registrado).
    final newVersion =
        newUnitCost != null && (current != null || newUnitCost > 0);
    if (newVersion) {
      version += 1;
      changed.add('costo'); // nunca el importe en la auditoría
      tx.set(_db.collection(_costs).doc('${ref.id}_$version'), {
        'utensilioId': ref.id,
        'version': version,
        'costoUnitario': newUnitCost,
        'vigenteDesde': FieldValue.serverTimestamp(),
        'creadoPor': actor.uid,
      });
    }
    tx.set(auditRef, {
      'accion': current == null
          ? AuditAction.crearUtensilio
          : AuditAction.editarUtensilio,
      'actorUid': actor.uid,
      'actorNombre': actor.nombre,
      'objetivo': ref.id,
      'campos': changed,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    if (current == null) {
      tx.set(ref, {
        'nombre': name,
        'disponible': 0,
        'enUso': 0,
        'stockMinimo': minStock,
        'activo': true,
        'versionCosto': version,
        'ultimaAuditoriaId': auditRef.id,
        'creadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    } else {
      tx.update(ref, {
        'nombre': name,
        'stockMinimo': minStock,
        'activo': active,
        'versionCosto': version,
        'ultimaAuditoriaId': auditRef.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
  });

  @override
  Future<void> registerMovement(
    AppUser actor, {
    required String utensilId,
    required UtensilKind kind,
    required int quantity,
    required String reason,
    WaiterRef? waiter,
    int sign = 1,
  }) => _db.runTransaction((tx) async {
    final ref = _db.collection(_utensils).doc(utensilId);
    final u = Utensil.tryParse(utensilId, (await tx.get(ref)).data() ?? {});
    if (u == null) throw const AppFailure('El utensilio ya no existe.');
    if (!u.active) throw const AppFailure('El utensilio está desactivado.');
    final assignmentRef = waiter == null
        ? null
        : _db
              .collection(_assignments)
              .doc(UtensilAssignment.idFor(utensilId, waiter.uid));
    final held = assignmentRef == null
        ? 0
        : (UtensilAssignment.tryParse(
                (await tx.get(assignmentRef)).data() ?? {},
              )?.quantity ??
              0);

    final int dAvailable;
    final int dInUse;
    switch (kind) {
      case UtensilKind.entrega:
        dAvailable = -quantity;
        dInUse = quantity;
      case UtensilKind.devolucion:
        dAvailable = quantity;
        dInUse = -quantity;
      case UtensilKind.perdida || UtensilKind.dano || UtensilKind.deterioro:
        dAvailable = 0;
        dInUse = -quantity;
      case UtensilKind.alta:
        dAvailable = quantity;
        dInUse = 0;
      case UtensilKind.ajuste:
        dAvailable = sign * quantity;
        dInUse = 0;
    }
    final available = u.available + dAvailable;
    final inUse = u.inUse + dInUse;
    if (available < 0) {
      throw AppFailure('No hay suficientes disponibles (${u.available}).');
    }
    if (kind.toWaiter && held + dInUse < 0) {
      throw AppFailure(
        'Esa persona solo tiene $held en uso de este utensilio.',
      );
    }
    final move = _db.collection(_moves).doc();
    tx.set(move, {
      'utensilioId': utensilId,
      'utensilioNombre': u.name,
      'tipo': kind.name,
      'cantidad': quantity,
      'deltaDisponible': dAvailable,
      'deltaEnUso': dInUse,
      'disponibleResultante': available,
      'enUsoResultante': inUse,
      if (waiter != null) 'meseroId': waiter.uid,
      if (waiter != null) 'meseroNombre': waiter.name,
      'versionCosto': u.costVersion,
      'motivo': reason,
      'creadoPor': actor.uid,
      'creadoPorNombre': actor.nombre,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    tx.update(ref, {
      'disponible': available,
      'enUso': inUse,
      'ultimoMovimiento': move.id,
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
    if (assignmentRef != null) {
      tx.set(assignmentRef, {
        'utensilioId': utensilId,
        'meseroId': waiter!.uid,
        'meseroNombre': waiter.name,
        'cantidad': held + dInUse,
        'ultimoMovimiento': move.id,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
  });
}
