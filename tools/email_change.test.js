const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeEmail, validateNewEmail, planEmailChange } = require('./lib/email_change');

test('normaliza espacios y mayúsculas', () => {
  assert.equal(normalizeEmail('  Ana@Gmail.COM '), 'ana@gmail.com');
});

test('valida formato y que sea distinto al actual', () => {
  assert.deepEqual(validateNewEmail('ana@gmail.com', 'sprad@granjaazul.com'), []);
  assert.equal(validateNewEmail('sin-arroba', 'x@y.com').length, 1);
  assert.equal(validateNewEmail('x@y.com', 'x@y.com').length, 1);
});

test('plan completo cuando ambos tienen el correo viejo', () => {
  const p = planEmailChange({ authEmail: 'a@x.com', profileEmail: 'a@x.com', newEmail: 'n@x.com' });
  assert.deepEqual(p.steps, ['auth', 'firestore']);
});

test('reanuda si Auth ya cambió pero Firestore no', () => {
  const p = planEmailChange({ authEmail: 'n@x.com', profileEmail: 'a@x.com', newEmail: 'n@x.com' });
  assert.deepEqual(p.steps, ['firestore']);
});

test('reanuda si Firestore ya cambió pero Auth no', () => {
  const p = planEmailChange({ authEmail: 'a@x.com', profileEmail: 'n@x.com', newEmail: 'n@x.com' });
  assert.deepEqual(p.steps, ['auth']);
});

test('sin pasos si ya está hecho', () => {
  const p = planEmailChange({ authEmail: 'n@x.com', profileEmail: 'n@x.com', newEmail: 'n@x.com' });
  assert.deepEqual(p.steps, []);
  assert.equal(p.error, undefined);
});

test('se niega si Auth y Firestore ya divergen de forma inesperada', () => {
  const p = planEmailChange({ authEmail: 'a@x.com', profileEmail: 'b@x.com', newEmail: 'n@x.com' });
  assert.ok(p.error);
  assert.deepEqual(p.steps, []);
});
