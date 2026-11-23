// Validación manual de `FirestoreOrderRepository.advanceKitchen` (Fase 8B)
// contra Firestore REAL de un proyecto Firebase AISLADO de pruebas.
//
// NUNCA contra producción: se niega a correr si el proyecto es
// `la-granja-azul-app`, si su id no contiene «test» o «prueba» o si
// `LIVE_CONFIRM` no repite el id. Pasos y requisitos:
// `docs/VALIDACION_FIREBASE_REAL.md`.
//
// Ejecuta el código real de la app (repositorios de Firestore), no una copia.
// Se siembra con una cuenta Admin y se avanza el pedido con Cocina o Admin.
// Cada resultado se clasifica en: OK, rechazo de la APP (`AppFailure`, no llegó
// a escribir) o rechazo de FIRESTORE (`FirebaseException`: reglas, permisos o
// límite de accesos; el cliente no distingue entre ellos, por eso el barrido).
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:granja_azul/core/error/app_failure.dart';
import 'package:granja_azul/features/inventory/models/inventory_models.dart';
import 'package:granja_azul/features/inventory/repositories/firestore_inventory_repository.dart';
import 'package:granja_azul/features/menu/models/dish.dart';
import 'package:granja_azul/features/menu/models/menu_category.dart';
import 'package:granja_azul/features/menu/repositories/firestore_menu_repository.dart';
import 'package:granja_azul/features/orders/models/restaurant_order.dart';
import 'package:granja_azul/features/orders/repositories/firestore_order_repository.dart';
import 'package:granja_azul/features/tables/repositories/firestore_table_repository.dart';

const _apiKey = String.fromEnvironment('LIVE_API_KEY');
const _appId = String.fromEnvironment('LIVE_APP_ID');
const _senderId = String.fromEnvironment('LIVE_SENDER_ID');
const _projectId = String.fromEnvironment('LIVE_PROJECT_ID');
const _confirm = String.fromEnvironment('LIVE_CONFIRM');
const _adminEmail = String.fromEnvironment('LIVE_ADMIN_EMAIL');
const _adminPassword = String.fromEnvironment('LIVE_ADMIN_PASSWORD');
const _cocinaEmail = String.fromEnvironment('LIVE_COCINA_EMAIL');
const _cocinaPassword = String.fromEnvironment('LIVE_COCINA_PASSWORD');

/// Primera mesa que usa la prueba (una por pedido: un pedido registrado
/// mantiene su mesa ocupada). Cámbiala para repetir la prueba en el mismo
/// proyecto. Las mesas son números de 1 a 9999.
const _tableBase = int.fromEnvironment('LIVE_TABLE_BASE', defaultValue: 9100);

const _productionProject = 'la-granja-azul-app';
const _maxSupplies = 8;
const _stockPerSupply = 100000; // 100 kg en milésimas.
const _portion = 1000; // 1 kg por insumo y por porción.
const _forcedNeed = 500000; // Más que el stock: faltante en cada insumo.

void _log(String message) {
  // ignore: avoid_print
  print(message);
}

/// Motivo por el que NO se puede correr, o null si las guardas se cumplen.
String? _guard() {
  if (_projectId.isEmpty) return 'Falta LIVE_PROJECT_ID.';
  if (_projectId == _productionProject) {
    return 'Rechazado: es el proyecto de PRODUCCIÓN.';
  }
  final id = _projectId.toLowerCase();
  if (!id.contains('test') && !id.contains('prueba')) {
    return 'Rechazado: el id del proyecto debe contener «test» o «prueba».';
  }
  if (_confirm != _projectId) {
    return 'Rechazado: LIVE_CONFIRM debe ser igual a LIVE_PROJECT_ID.';
  }
  for (final entry in {
    'LIVE_API_KEY': _apiKey,
    'LIVE_APP_ID': _appId,
    'LIVE_SENDER_ID': _senderId,
    'LIVE_ADMIN_EMAIL': _adminEmail,
    'LIVE_ADMIN_PASSWORD': _adminPassword,
    'LIVE_COCINA_EMAIL': _cocinaEmail,
    'LIVE_COCINA_PASSWORD': _cocinaPassword,
  }.entries) {
    if (entry.value.isEmpty) return 'Falta ${entry.key}.';
  }
  return null;
}

enum _Outcome { ok, app, rules, firestore, other, setup }

class _Result {
  _Result(this.label, this.expected, this.orderId);
  final String label;
  final _Outcome expected;
  final String? orderId;
  _Outcome outcome = _Outcome.setup;
  String detail = '';
  bool? markerExists;
  bool? exceptionExists;
  bool get pass => outcome == expected;
}

class _Check {
  _Check(this.db)
    : inventory = FirestoreInventoryRepository(db),
      menu = FirestoreMenuRepository(db),
      tables = FirestoreTableRepository(db),
      orders = FirestoreOrderRepository(db);

  final FirebaseFirestore db;
  final FirestoreInventoryRepository inventory;
  final FirestoreMenuRepository menu;
  final FirestoreTableRepository tables;
  final FirestoreOrderRepository orders;

  final results = <_Result>[];
  final supplyIds = <String>[];
  final supplyNames = <String>[];
  var _nextTable = _tableBase;

  Future<String> _signIn(String email, String password) async {
    final auth = FirebaseAuth.instance;
    await auth.signOut();
    final cred = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user!.uid;
  }

  Future<String> _signInAdmin() => _signIn(_adminEmail, _adminPassword);
  Future<String> _signInCocina() => _signIn(_cocinaEmail, _cocinaPassword);

  /// Siembra (como Admin) 9 insumos con stock, la categoría y los platos con
  /// receta de 1 a 9 insumos, más uno cuyo consumo supera el stock.
  Future<void> seed(String adminUid) async {
    for (var i = 1; i <= _maxSupplies + 1; i++) {
      final name = 'TEST_Insumo $i';
      var found = await db
          .collection('insumos')
          .where('nombre', isEqualTo: name)
          .get();
      if (found.docs.isEmpty) {
        await inventory.createSupply(name, SupplyUnit.kg, 0, 100);
        found = await db
            .collection('insumos')
            .where('nombre', isEqualTo: name)
            .get();
        await inventory.moveStock(
          found.docs.first.id,
          MovementKind.entrada,
          _stockPerSupply,
          'TEST siembra',
          actorUid: adminUid,
        );
      }
      supplyIds.add(found.docs.first.id);
      supplyNames.add(name);
    }
    await menu.saveCategory(
      const MenuCategory(id: 'test_cat', name: 'TEST categoria'),
    );
    for (var n = 1; n <= _maxSupplies + 1; n++) {
      await _saveDish('test_r$n', n, _portion, adminUid);
    }
    await _saveDish('test_rf', _maxSupplies, _forcedNeed, adminUid);
  }

  Future<void> _saveDish(String id, int supplies, int qty, String uid) async {
    await menu.saveDish(
      Dish(
        id: id,
        name: 'TEST plato $id',
        description: 'Plato de prueba ($supplies insumos)',
        categoryId: 'test_cat',
        price: 10,
        imageUrl: '',
      ),
    );
    await inventory.saveRecipe(id, [
      for (var i = 0; i < supplies; i++)
        RecipeIngredient(supplyId: supplyIds[i], name: supplyNames[i], qty: qty),
    ], actorUid: uid);
  }

  /// Un pedido registrado (pendiente en cocina) de una porción de [dish],
  /// creado como Admin en una mesa nueva.
  Future<String> _registerOrder(String adminUid, String dish) async {
    final table = '${_nextTable++}';
    await tables.saveTable(table, 4, true, create: true);
    final order = await orders.openOrder(table, adminUid);
    await orders.addItem(order, dish, 1, '');
    await orders.changeStatus(order, OrderStatus.registrado);
    return order;
  }

  /// Escenario: registra el pedido, lo pasa a «Preparando» y a «Listo» con
  /// [actor] (`cocina` o `admin`). Con [tryWithoutForce] intenta primero sin
  /// motivo de forzado y luego con él.
  Future<void> scenario(
    String label, {
    required String actor,
    required String dish,
    required _Outcome expected,
    String? forceReason,
    bool tryWithoutForce = false,
  }) async {
    final adminUid = await _signInAdmin();
    String? orderId;
    try {
      orderId = await _registerOrder(adminUid, dish);
    } on Object catch (e) {
      final failed = _Result(label, expected, null)
        ..detail = 'La preparación falló antes de probar: ${_describe(e)}';
      results.add(failed);
      return;
    }
    final result = _Result(label, expected, orderId);
    results.add(result);
    try {
      final uid = actor == 'cocina'
          ? await _signInCocina()
          : await _signInAdmin();
      await orders.advanceKitchen(orderId, KitchenStatus.preparando, uid);
      if (tryWithoutForce) {
        try {
          await orders.advanceKitchen(orderId, KitchenStatus.listo, uid);
          result
            ..outcome = _Outcome.other
            ..detail = 'Sin motivo debía rechazarse y pasó.';
          return;
        } on AppFailure catch (e) {
          result.detail = 'Sin motivo: APP rechaza («${e.code ?? e.message}»). ';
        }
      }
      await orders.advanceKitchen(
        orderId,
        KitchenStatus.listo,
        uid,
        forceReason: forceReason,
      );
      result
        ..outcome = _Outcome.ok
        ..detail += 'Pasó a «Listo».';
    } on AppFailure catch (e) {
      result
        ..outcome = _Outcome.app
        ..detail += 'APP (AppFailure): ${e.message}';
    } on FirebaseException catch (e) {
      result
        ..outcome = e.code == 'permission-denied'
            ? _Outcome.rules
            : _Outcome.firestore
        ..detail += 'FIRESTORE (${e.code}): ${e.message ?? ''}';
    } on Object catch (e) {
      result
        ..outcome = _Outcome.other
        ..detail += _describe(e);
    }
  }

  String _describe(Object e) => switch (e) {
    AppFailure() => 'APP (AppFailure): ${e.message}',
    FirebaseException() => 'FIRESTORE (${e.code}): ${e.message ?? ''}',
    _ => '${e.runtimeType}',
  };

  /// Con Admin, comprueba qué documentos quedaron: el marcador del descuento y,
  /// en el forzado, la excepción.
  Future<void> verifyDocuments() async {
    await _signInAdmin();
    for (final r in results) {
      final id = r.orderId;
      if (id == null) continue;
      r.markerExists = (await db.collection('descuentosInventario').doc(id).get())
          .exists;
      if (r.label.contains('forzado')) {
        r.exceptionExists =
            (await db.collection('excepcionesInventario').doc(id).get()).exists;
      }
    }
  }
}

String _name(_Outcome o) => switch (o) {
  _Outcome.ok => 'OK',
  _Outcome.app => 'APP rechaza',
  _Outcome.rules => 'FIRESTORE permission-denied',
  _Outcome.firestore => 'FIRESTORE otro error',
  _Outcome.other => 'OTRO',
  _Outcome.setup => 'NO SE PROBÓ',
};

Future<int> _run() async {
  final blocked = _guard();
  if (blocked != null) {
    _log(blocked);
    return 2;
  }
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
    ),
  );
  _log('Proyecto de pruebas: $_projectId');
  final check = _Check(FirebaseFirestore.instance);

  final adminUid = await check._signInAdmin();
  await check.seed(adminUid);
  _log('Siembra lista (9 insumos, platos con receta de 1 a 9 insumos).');

  // Barrido con Cocina: el mayor n que pasa y el primero que falla delatan un
  // límite de accesos de las reglas (todo lo demás es igual entre filas).
  var maxCocina = 0;
  for (var n = 1; n <= _maxSupplies; n++) {
    await check.scenario(
      'Cocina, normal, $n insumo${n == 1 ? '' : 's'}',
      actor: 'cocina',
      dish: 'test_r$n',
      expected: _Outcome.ok,
    );
    if (check.results.last.outcome == _Outcome.ok) maxCocina = n;
  }
  await check.scenario(
    'Admin, normal, $_maxSupplies insumos',
    actor: 'admin',
    dish: 'test_r$_maxSupplies',
    expected: _Outcome.ok,
  );
  await check.scenario(
    'Cocina, 9 insumos (debe rechazar la APP)',
    actor: 'cocina',
    dish: 'test_r${_maxSupplies + 1}',
    expected: _Outcome.app,
  );
  // Último: deja en cero el stock de los insumos 1 a 8.
  await check.scenario(
    'Admin, forzado, $_maxSupplies insumos con faltante',
    actor: 'admin',
    dish: 'test_rf',
    expected: _Outcome.ok,
    forceReason: 'TEST forzado por validacion en proyecto aislado',
    tryWithoutForce: true,
  );

  await check.verifyDocuments();

  var failed = 0;
  _log('\nRESULTADOS (esperado → obtenido)');
  for (final r in check.results) {
    if (!r.pass) failed++;
    final docs = r.orderId == null
        ? ''
        : ' · marcador=${r.markerExists}'
              '${r.exceptionExists == null ? '' : ' · excepción=${r.exceptionExists}'}';
    _log(
      '${r.pass ? 'PASA ' : 'FALLA'} ${r.label}: '
      '${_name(r.expected)} → ${_name(r.outcome)}$docs\n       ${r.detail}',
    );
  }
  _log('\nMayor n con Cocina que pasó en este barrido: $maxCocina');
  _log(
    failed == 0
        ? 'Todo coincide con lo esperado.'
        : '$failed escenario(s) no coinciden. Si un permission-denied aparece '
              'a partir de cierto n con Cocina y no con Admin, es el límite de '
              'accesos de las reglas: ver docs/VALIDACION_FIREBASE_REAL.md.',
  );
  return failed == 0 ? 0 : 1;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Validación de advanceKitchen: ver consola')),
      ),
    ),
  );
  var code = 3;
  try {
    code = await _run();
  } on Object catch (e) {
    _log('La validación se interrumpió: ${e.runtimeType}');
  }
  exit(code);
}
