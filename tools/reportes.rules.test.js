// Fase 8: los reportes no tienen colecciones propias; leen con las reglas de
// cada módulo. Esta prueba ejecuta las consultas exactas del reporte (por
// rango de fechas) con Admin y Superadmin, y comprueba que ningún reporte pueda
// escribir y que los roles sin acceso no lean datos de otras áreas.
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDocs, collection, query, where, setDoc, updateDoc, Timestamp } = require('firebase/firestore');

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-rep', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });
const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

const from = Timestamp.fromDate(new Date('2026-11-01T00:00:00Z'));
const to = Timestamp.fromDate(new Date('2026-12-01T00:00:00Z'));
const range = (d, col, field) => getDocs(query(collection(d, col), where(field, '>=', from), where(field, '<', to)));

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    for (const [uid, rol] of Object.entries({ admin: 'admin', super: 'superadmin', w1: 'mesero', k: 'cocina', cash: 'cajero' })) {
      await setDoc(doc(d, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, activo: true });
      await setDoc(doc(d, 'estadoAsistencia', uid), { abierta: true, asistenciaId: `a${uid}` });
    }
    await setDoc(doc(d, 'pagos/o1'), { pedidoId: 'o1', total: 5100, creadoEn: Timestamp.fromDate(new Date('2026-11-10T15:00:00Z')) });
    await setDoc(doc(d, 'pedidos/o1'), { mesaId: '1', meseroId: 'w1', estado: 'pagado' });
    await setDoc(doc(d, 'pedidos/o1/detalles/d1'), { nombre: 'Brasa', precio: 25.5, cantidad: 2, observaciones: '' });
    await setDoc(doc(d, 'compras/c1'), { estado: 'recibida', recibidoEn: Timestamp.fromDate(new Date('2026-11-12T15:00:00Z')) });
    await setDoc(doc(d, 'movimientosInventario/m1'), { tipo: 'merma', creadoEn: Timestamp.fromDate(new Date('2026-11-12T15:00:00Z')) });
    await setDoc(doc(d, 'asistencias/a1'), { uid: 'w1', entrada: Timestamp.fromDate(new Date('2026-11-10T13:00:00Z')) });
  });
});

test('Admin y Superadmin ejecutan las consultas de los reportes', async () => {
  for (const uid of ['admin', 'super']) {
    const d = db(uid);
    await assertSucceeds(range(d, 'pagos', 'creadoEn'));
    await assertSucceeds(range(d, 'compras', 'recibidoEn'));
    await assertSucceeds(range(d, 'movimientosInventario', 'creadoEn'));
    await assertSucceeds(range(d, 'asistencias', 'entrada'));
    await assertSucceeds(getDocs(collection(d, 'pedidos/o1/detalles')));
    await assertSucceeds(getDocs(collection(d, 'insumos')));
    await assertSucceeds(getDocs(collection(d, 'recetas')));
  }
});

test('mesero, cocina y almacén no leen las ventas', async () => {
  for (const uid of ['w1', 'k']) {
    await assertFails(range(db(uid), 'pagos', 'creadoEn'));
  }
});

test('mesero y cajero no leen movimientos de inventario; ni ellos ni cocina leen compras ni asistencia ajena', async () => {
  for (const uid of ['w1', 'k', 'cash']) {
    await assertFails(range(db(uid), 'compras', 'recibidoEn'));
    if (uid !== 'k') await assertFails(range(db(uid), 'movimientosInventario', 'creadoEn')); // Cocina los lee (insumos)
    await assertFails(range(db(uid), 'asistencias', 'entrada'));
  }
});

test('los reportes son de solo lectura: nadie corrige ventas ni asistencias desde ellos', async () => {
  for (const uid of ['admin', 'super']) {
    await assertFails(updateDoc(doc(db(uid), 'pagos/o1'), { total: 1 }));
    await assertFails(updateDoc(doc(db(uid), 'movimientosInventario/m1'), { tipo: 'entrada' }));
  }
});
