// Pruebas de la ejecución controlada de la purga con los emuladores de
// Firestore y Authentication y datos ficticios. Nunca tocan producción.
//
//   npm run test:rules   (levanta ambos emuladores)
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const admin = require('firebase-admin');
const { AUTHORIZED, collectPurgePlan } = require('./lib/terminal_purge_plan');
const { buildBackup, sha256 } = require('./lib/terminal_purge_backup');
const { authorizedRefs, executePurge, verifyAfter } = require('./lib/terminal_purge_exec');

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Estas pruebas exigen los emuladores de Firestore y Auth ' +
    '(FIRESTORE_EMULATOR_HOST y FIREBASE_AUTH_EMULATOR_HOST). Abortando.');
}

const PROJECT = 'la-granja-azul-app';
const app = admin.initializeApp({ projectId: PROJECT }, 'purge-exec-test');
const auth = admin.auth(app);
const db = admin.firestore(app);

/** Vacía SOLO los emuladores (las variables de emulador ya se comprobaron). */
async function wipe() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/accounts`, { method: 'DELETE' });
}

async function seed() {
  await wipe();
  for (const uid of AUTHORIZED.accountUids) {
    await auth.createUser({ uid, email: `${uid.toLowerCase()}@terminal.test`, password: 'x'.repeat(12) });
    await db.doc(`terminales/${uid}`).set({ nombre: `Tablet ${uid}`, activo: true });
    await db.doc(`terminalClaves/${uid}`).set({ clave: 'k'.repeat(40) });
    await db.doc(`terminalPruebas/${uid}`).set({ ok: true });
    await db.doc(`asistencias/${uid}-hist`).set({ uid: 'w1', terminalId: uid, origen: 'qr' });
    await db.doc(`solicitudesEliminacionTerminal/${uid}`).set({ nombre: 'x' });
  }
  for (const id of AUTHORIZED.tokenIds) {
    await db.doc(`qrTokens/${id}`).set({ uid: 'w1', tipo: 'entrada', terminalId: null, usadoEn: null, creadoEn: new Date(0) });
  }
  await db.doc('qrTokens/nuevo1').set({ generadorUid: 'adm', usadoEn: new Date(), creadoEn: new Date() });
  await db.doc('qrTokens/usado1').set({ uid: 'w', tipo: 'entrada', usadoEn: new Date(), creadoEn: new Date() });
  for (const id of AUTHORIZED.auditIds) {
    await db.doc(`auditoria/${id}`).set({ accion: 'autorizar_terminal', actorUid: 'boss', objetivo: AUTHORIZED.accountUids[0], campos: [] });
  }
  await db.doc('auditoria/ajena').set({ accion: 'crear_pedido', actorUid: 'boss', objetivo: 'p1', campos: [] });
  await db.doc('usuarios/boss').set({ rol: 'admin', activo: true });
  await auth.createUser({ uid: 'normal1', email: 'normal1@staff.test', password: 'x'.repeat(12) });
}

async function makeBackup() {
  const plan = await collectPurgePlan({ auth, db });
  const backup = await buildBackup({ auth, db, plan });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'purga-test-'));
  for (const f of backup.files) {
    fs.mkdirSync(path.dirname(path.join(dir, f.file)), { recursive: true });
    fs.writeFileSync(path.join(dir, f.file), f.content, 'utf8');
  }
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({
    cuentasAuth: backup.accounts, documentos: backup.documents,
    archivos: backup.files.map((f) => ({ file: f.file, sha256: f.sha256 })),
  }));
  return dir;
}

const exists = async (ref) => (await db.doc(ref).get()).exists;

test('elimina exactamente los 38 autorizados y conserva todo lo demás', async () => {
  await seed();
  const dir = await makeBackup();
  const result = await executePurge({ auth, db, backupDir: dir });
  assert.equal(result.ok, true, JSON.stringify(result));
  assert.equal(result.eliminados.length, 38);
  const check = await verifyAfter({ auth, db, antes: result.antes, despues: result.despues });
  assert.deepEqual(check.fallos, []);
  for (const ref of authorizedRefs()) assert.equal(await exists(ref), false, ref);
  for (const ref of ['qrTokens/nuevo1', 'qrTokens/usado1', 'auditoria/ajena', 'usuarios/boss',
    ...AUTHORIZED.accountUids.flatMap((u) => [`terminalClaves/${u}`, `solicitudesEliminacionTerminal/${u}`, `asistencias/${u}-hist`])]) {
    assert.equal(await exists(ref), true, ref);
  }
  assert.equal((await auth.getUser('normal1')).uid, 'normal1');
});

test('aborta sin eliminar nada si un token cambió de estado', async () => {
  await seed();
  const dir = await makeBackup();
  await db.doc(`qrTokens/${AUTHORIZED.tokenIds[0]}`).update({ usadoEn: new Date() });
  const result = await executePurge({ auth, db, backupDir: dir });
  assert.equal(result.ok, false);
  assert.equal(result.eliminados.length, 0);
  for (const ref of authorizedRefs().filter((r) => !r.includes(AUTHORIZED.tokenIds[0]))) assert.equal(await exists(ref), true, ref);
  assert.equal((await auth.getUser(AUTHORIZED.accountUids[0])).disabled, false);
});

test('aborta si el respaldo está alterado o incompleto', async () => {
  await seed();
  const dir = await makeBackup();
  const victim = path.join(dir, `firestore/qrTokens/${AUTHORIZED.tokenIds[1]}.json`);
  fs.writeFileSync(victim, `${fs.readFileSync(victim, 'utf8')} `, 'utf8');
  const bad = await executePurge({ auth, db, backupDir: dir });
  assert.equal(bad.ok, false);
  assert.match(bad.abortado.join(' '), /hash distinto/);
  const empty = await executePurge({ auth, db, backupDir: fs.mkdtempSync(path.join(os.tmpdir(), 'vacio-')) });
  assert.equal(empty.ok, false);
  assert.equal(await exists(`terminales/${AUTHORIZED.accountUids[0]}`), true);
  assert.ok(sha256('x'));
});

test('aborta si una asistencia nueva referencia un token autorizado', async () => {
  await seed();
  const dir = await makeBackup();
  await db.doc('asistencias/nueva').set({ uid: 'w', tokenId: AUTHORIZED.tokenIds[2] });
  const result = await executePurge({ auth, db, backupDir: dir });
  assert.equal(result.ok, false);
  assert.equal(result.eliminados.length, 0);
  assert.equal(await exists(`qrTokens/${AUTHORIZED.tokenIds[2]}`), true);
});

test('ante un fallo parcial se detiene e informa eliminados y pendientes', async () => {
  await seed();
  const dir = await makeBackup();
  let calls = 0;
  const flaky = new Proxy(db, {
    get(target, prop) {
      if (prop !== 'doc') return Reflect.get(target, prop).bind ? Reflect.get(target, prop).bind(target) : Reflect.get(target, prop);
      return (ref) => {
        const real = target.doc(ref);
        return new Proxy(real, {
          get(r, p) {
            if (p === 'delete') return async (...a) => { if (++calls === 3) throw new Error('fallo simulado'); return r.delete(...a); };
            const v = r[p];
            return typeof v === 'function' ? v.bind(r) : v;
          },
        });
      };
    },
  });
  const result = await executePurge({ auth, db: flaky, backupDir: dir });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'fallo simulado');
  assert.equal(result.eliminados.length, 2);
  assert.equal(result.eliminados.length + result.pendientes.length, 38);
  assert.equal((await auth.getUser(AUTHORIZED.accountUids[0])).uid, AUTHORIZED.accountUids[0]);
});

test('la CLI rechaza ejecutarse sin respaldo ni confirmación literal', () => {
  const run = (...args) => spawnSync(process.execPath, [path.join(__dirname, 'execute_terminal_purge.js'), ...args],
    { encoding: 'utf8', env: { ...process.env, GOOGLE_APPLICATION_CREDENTIALS: '' } });
  assert.notEqual(run().status, 0);
  assert.match(run('--backup', 'x').stderr, /confirmar|No se eliminó/);
  assert.match(run('--confirmar', 'ELIMINAR-38').stderr, /No se eliminó/);
  assert.match(run('--confirmar', 'si', '--backup', 'x').stderr, /No se eliminó/);
});
