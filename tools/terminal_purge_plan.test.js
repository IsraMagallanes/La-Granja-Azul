// Pruebas de la simulación de purga de terminales con los emuladores de
// Firestore y Authentication y datos ficticios. Nunca tocan producción: sin las
// variables de emulador la suite aborta antes de conectar.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { AUTHORIZED, collectPurgePlan, formatReport } = require('./lib/terminal_purge_plan');

const { buildBackup, candidatesFromPlan, candidatesFromReport } = require('./lib/terminal_purge_backup');

const SOURCES = ['lib/terminal_purge_plan.js', 'purge_terminals_dryrun.js', 'lookup_missing_audit.js',
  'lib/terminal_purge_backup.js', 'prepare_purge_backup.js']
  .map((f) => [f, fs.readFileSync(path.join(__dirname, f), 'utf8')]);

// Pruebas estáticas: se ejecutan siempre, incluso sin emuladores.
test('el código de la simulación no contiene operaciones de escritura ni eliminación', () => {
  const forbidden = [
    /\.delete\s*\(/, /deleteUser/, /deleteUsers/, /\.commit\s*\(/, /\.batch\s*\(/,
    /\.set\s*\(/, /\.update\s*\((?!text\)\.digest)/, // `hash.update(text).digest` es local /\.create\s*\(/, /\.add\s*\(/, /runTransaction/,
    /bulkWriter/i, /recursiveDelete/, /setCustomUserClaims/, /updateUser/, /createUser/,
    /revokeRefreshTokens/, /FieldValue/,
  ];
  for (const [file, text] of SOURCES) {
    // Se ignoran comentarios para no confundir la documentación con código.
    const code = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const re of forbidden) assert.doesNotMatch(code, re, `${file} contiene ${re}`);
  }
});

test('los 21 ids de auditoría tienen 20 caracteres', () => {
  for (const id of AUTHORIZED.auditIds) assert.equal(id.length, 20, id);
  assert.ok(AUTHORIZED.auditIds.includes('4IQETUcGGBoGOQ2K4mdZ'));
  assert.ok(AUTHORIZED.auditIds.includes('gmf76Ifgkjl2KJu9kSoB'));
});

test('no admite opciones ni modo de eliminación', () => {
  const cli = SOURCES.find(([f]) => f === 'purge_terminals_dryrun.js')[1];
  assert.match(cli, /process\.argv\.length > 2/);
  assert.doesNotMatch(cli, /--(delete|execute|apply|purge|force)/i);
});

test('la lista autorizada tiene 3 cuentas, 8 tokens y 21 auditorías sin duplicados', () => {
  assert.equal(AUTHORIZED.accountUids.length, 3);
  assert.equal(AUTHORIZED.tokenIds.length, 8);
  assert.equal(AUTHORIZED.auditIds.length, 21);
  for (const list of [AUTHORIZED.accountUids, AUTHORIZED.tokenIds, AUTHORIZED.auditIds]) {
    assert.equal(new Set(list).size, list.length);
  }
});

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const app = admin.initializeApp({ projectId: 'la-granja-azul-app' }, 'purge-plan-test');
const auth = admin.auth(app);
const db = admin.firestore(app);

async function snapshotAll() {
  const state = {};
  for (const col of await db.listCollections()) {
    for (const d of (await col.get()).docs) state[`${col.id}/${d.id}`] = JSON.stringify(d.data());
  }
  const users = [];
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    users.push(...page.users.map((u) => `${u.uid}|${u.email}|${u.disabled}`));
    token = page.pageToken;
  } while (token);
  return { state, users: users.sort() };
}

/** Vacía SOLO los emuladores: otros archivos de prueba comparten el mismo estado. */
async function wipe() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/la-granja-azul-app/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/la-granja-azul-app/accounts`, { method: 'DELETE' });
}

async function seed() {
  await wipe();
  for (const uid of AUTHORIZED.accountUids) {
    await auth.createUser({ uid, email: `${uid.toLowerCase()}@terminal.test`, password: 'x'.repeat(12) });
    await db.doc(`terminales/${uid}`).set({ nombre: `Tablet ${uid}`, activo: true });
    await db.doc(`terminalClaves/${uid}`).set({ clave: 'k'.repeat(40) });
    await db.doc(`terminalPruebas/${uid}`).set({ ok: true });
    await db.doc(`asistencias/${uid}-hist`).set({ uid: 'w1', terminalId: uid, origen: 'qr' });
  }
  for (const id of AUTHORIZED.tokenIds) {
    await db.doc(`qrTokens/${id}`).set({ uid: 'w1', tipo: 'entrada', terminalId: null, usadoEn: null, creadoEn: new Date(0) });
  }
  await db.doc('qrTokens/nuevo1').set({ generadorUid: 'adm', usadoEn: null, creadoEn: new Date() });
  for (const id of AUTHORIZED.auditIds) {
    await db.doc(`auditoria/${id}`).set({ accion: 'autorizar_terminal', actorUid: 'boss', objetivo: AUTHORIZED.accountUids[0], campos: [] });
  }
  await db.doc('auditoria/reciente').set({ accion: 'crear_pedido', actorUid: 'boss', objetivo: 'p1', campos: [] });
}

test('simulación completa: totales, informe y ningún cambio en los datos', async () => {
  await seed();
  const before = await snapshotAll();
  const plan = await collectPurgePlan({ auth, db });
  const after = await snapshotAll();

  assert.deepEqual(plan.totales,
    { cuentasAuth: 3, terminales: 3, terminalPruebas: 3, qrTokens: 8, auditoria: 21, general: 38 });
  assert.deepEqual(plan.diferencias, []);
  assert.equal(plan.conservados.qrTokensSistemaNuevo, 1);
  assert.ok(plan.cuentas.every((c) => c.documentosAsociados.terminalClaves));
  assert.deepEqual(after, before, 'ni Firestore ni Authentication deben cambiar');

  const text = formatReport(plan, 'p');
  assert.match(text, /TOTAL GENERAL             : 38/);
  assert.match(text, /SIMULACIÓN/);
  for (const uid of AUTHORIZED.accountUids) {
    assert.ok(!text.includes(`${uid.toLowerCase()}@terminal.test`), 'no debe imprimir correos completos');
  }
});

test('el respaldo cubre exactamente los candidatos, sin hashes de contraseña, y no cambia nada', async () => {
  const plan = await collectPurgePlan({ auth, db });
  const before = await snapshotAll();
  const backup = await buildBackup({ auth, db, plan });
  assert.deepEqual(await snapshotAll(), before);
  assert.equal(backup.accounts, 3);
  assert.equal(backup.documents, 35);
  assert.deepEqual(backup.missing, []);
  assert.doesNotMatch(backup.files.map((f) => f.content).join(''), /passwordHash|passwordSalt/);
  assert.equal(backup.files.filter((f) => f.file.startsWith('firestore/')).length, 35);
  assert.deepEqual([...candidatesFromReport(formatReport(plan, 'p'))].sort(),
    [...candidatesFromPlan(plan)].sort());
});

test('excluye tokens usados o referenciados, auditorías de otra acción, y documentos ajenos', async () => {
  await db.doc(`qrTokens/${AUTHORIZED.tokenIds[0]}`).update({ usadoEn: new Date() });
  await db.doc('asistencias/ref').set({ uid: 'w', tokenId: AUTHORIZED.tokenIds[1] });
  await db.doc(`qrTokens/${AUTHORIZED.tokenIds[2]}`).delete();
  await db.doc(`auditoria/${AUTHORIZED.auditIds[0]}`).update({ accion: 'crear_pedido' });
  await db.doc('terminales/ajena').set({ nombre: 'Otra', activo: true });
  await db.doc(`usuarios/${AUTHORIZED.accountUids[2]}`).set({ rol: 'cajero', activo: true });

  const before = await snapshotAll();
  const plan = await collectPurgePlan({ auth, db });
  assert.deepEqual(await snapshotAll(), before);

  const why = (list, id) => list.find((x) => x.id === id)?.motivos.join(' ');
  assert.match(why(plan.tokens.excluidos, AUTHORIZED.tokenIds[0]), /ahora está usado/);
  assert.match(why(plan.tokens.excluidos, AUTHORIZED.tokenIds[1]), /asistencia lo referencia/);
  assert.match(why(plan.tokens.excluidos, AUTHORIZED.tokenIds[2]), /no existe/);
  assert.match(why(plan.auditoria.excluidos, AUTHORIZED.auditIds[0]), /no es del sistema antiguo/);
  assert.equal(plan.cuentas[2].incluida, false);
  assert.match(plan.cuentas[2].motivos.join(' '), /criterio 2/);
  assert.equal(plan.terminales.excluidos.some((x) => x.id === 'ajena'), true);
  assert.equal(plan.totales.cuentasAuth, 2);
  assert.equal(plan.totales.qrTokens, 5);
  assert.equal(plan.totales.auditoria, 20);
  assert.equal(plan.totales.terminales, 2);
});
