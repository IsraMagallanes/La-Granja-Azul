// Cálculo reproducible de los límites de accesos de las reglas (sin emulador ni
// red). Comprueba que el máximo de 5 líneas por compra sale del presupuesto y que
// las reglas, la app y la migración usan el mismo número.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const budget = require('./lib/rule_access_budget');
const { MAX_PURCHASE_LINES } = require('./lib/supply_costs_migration');

const read = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8').replace(/\r\n/g, '\n');

test('recibir una compra cuesta 3 + 3n accesos: 18 con 5 líneas, 21 con 6', () => {
  assert.equal(budget.total(budget.receivePurchase(5)), 18);
  assert.equal(budget.total(budget.receivePurchase(6)), 21);
  assert.ok(budget.total(budget.receivePurchase(5)) <= budget.LIMIT_BATCH);
  assert.ok(budget.total(budget.receivePurchase(6)) > budget.LIMIT_BATCH);
});

test('el máximo de líneas deriva del presupuesto y coincide en reglas, app y migración', () => {
  const max = budget.maxPurchaseLines();
  assert.equal(max, 5);
  assert.equal(MAX_PURCHASE_LINES, max);
  assert.match(read('lib/features/inventory/services/inventory_service.dart'), new RegExp(`maxLines = ${max};`));
  const rules = read('firestore.rules');
  assert.match(rules, new RegExp(`n >= 1 && n <= ${max}\\n\\s+&& \\(n <= 0 \\|\\| purchaseLine`));
  assert.match(rules, new RegExp(`return n >= 1 && n <= ${max}\\n`)); // purchaseFullyMoved
  // sin rastro de las líneas 6 a 8 en las reglas de compras
  assert.doesNotMatch(rules, /purchaseLine\(ls\[5\]\)/);
  assert.doesNotMatch(rules, /id \+ '_5'/);
});

test('los demás escenarios nuevos caben en su límite con holgura', () => {
  for (const s of [budget.utensilDelivery(), budget.utensilCatalogEdit(), budget.supplyEdit(), budget.supplyCostWrite()]) {
    assert.ok(budget.total(s) <= s.limit, s.scenario);
  }
  assert.equal(budget.total(budget.utensilDelivery()), 6);
  assert.equal(budget.total(budget.utensilCatalogEdit()), 4);
});

test('la Fase 8B tras la optimización: 4 + 2n en el lote y ≤ 10 por operación', () => {
  assert.equal(budget.total(budget.kitchenReady(8)), 20); // antes 21
  assert.equal(budget.total(budget.kitchenReady(7)), 18);
  assert.ok(budget.total(budget.kitchenReady(8)) <= budget.LIMIT_BATCH);
  assert.ok(budget.total(budget.kitchenReady(9)) > budget.LIMIT_BATCH); // el máximo de 8 es el límite real
  const { n, ...ops } = budget.kitchenReadyPerOperation(8);
  for (const [name, v] of Object.entries(ops)) assert.ok(v <= budget.LIMIT_SINGLE, name);
});

test('las reglas de la Fase 8B ya no recorren todos los movimientos ni leen el pedido anterior', () => {
  const rules = read('firestore.rules');
  const fn = rules.slice(rules.indexOf('function consumptionDone'), rules.indexOf('function shortageItem') - 300);
  assert.equal((fn.match(/getAfter\(docPath\('movimientosInventario'/g) || []).length, 1);
  assert.match(rules, /d\.linea == 0 \|\| existsAfter\(docPath\('movimientosInventario'/);
  const marker = rules.slice(rules.indexOf('match /descuentosInventario/{order}'));
  assert.doesNotMatch(marker.slice(0, marker.indexOf('allow update, delete')), /\bget\(docPath\('pedidos'/);
});

test('la regla de costosInsumos no consulta otros documentos (no añade accesos a la recepción)', () => {
  const rules = read('firestore.rules');
  const block = rules.slice(rules.indexOf('match /costosInsumos/{id}'), rules.indexOf('match /costosInsumos/{id}') + 900);
  assert.doesNotMatch(block.slice(0, block.indexOf('allow delete')), /\b(get|getAfter|exists|existsAfter)\(/);
});

test('el movimiento de compra consulta el costo con un solo getAfter', () => {
  const rules = read('firestore.rules');
  const fn = rules.slice(rules.indexOf('function purchaseMovement'), rules.indexOf('function validConsumeMovement'));
  assert.equal((fn.match(/getAfter\(docPath\('costosInsumos'/g) || []).length, 1);
  assert.doesNotMatch(fn, /exists\(/);
});
