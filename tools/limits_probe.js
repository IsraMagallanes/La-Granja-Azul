#!/usr/bin/env node
/**
 * Sonda de límites de accesos de las reglas contra un proyecto Firebase SEPARADO.
 * El emulador no aplica los 10/20 accesos por petición; este script lo comprueba
 * de verdad. NUNCA contra producción: rechaza `la-granja-azul-app`.
 *
 * Preparación (una vez, por la persona responsable):
 *   1. Crear un proyecto Firebase de pruebas (p. ej. granja-azul-limites) con Firestore
 *      y Authentication activados, y una clave de cuenta de servicio de ESE proyecto.
 *   2. Desplegar en él las reglas actuales:  firebase deploy --only firestore:rules --project <id>
 *   3. Exportar GOOGLE_APPLICATION_CREDENTIALS (clave del proyecto de pruebas) y
 *      LIMITS_API_KEY (Web API key del proyecto de pruebas).
 *
 * Uso:
 *   node limits_probe.js --project <id> --i-confirm-separate-project [--keep]
 *
 * Qué hace: siembra datos, y con usuarios de prueba (custom token) intenta
 *   - recibir una compra de 5 líneas   → debe SER ACEPTADA (18 accesos calculados)
 *   - recibir una compra de 6 líneas   → debe SER RECHAZADA por las reglas (21 > 20)
 *   - una entrega de utensilios        → debe SER ACEPTADA (6 accesos)
 *   - Fase 8B: «Listo» con 8 insumos   → debe SER ACEPTADA (20 accesos, sin margen)
 *   - Fase 8B: «Listo» con 9 insumos   → debe SER RECHAZADA
 * Imprime una tabla y sale con código 1 si algún resultado difiere. Sin --keep borra
 * lo que sembró al terminar.
 */
const admin = require('firebase-admin');
const { initializeApp } = require('firebase/app');
const { getAuth, signInWithCustomToken } = require('firebase/auth');
const { getFirestore, doc, writeBatch, serverTimestamp } = require('firebase/firestore');

const PROD = 'la-granja-azul-app';
const args = process.argv.slice(2);
const opt = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const projectId = opt('--project');
if (!projectId || projectId === PROD || !args.includes('--i-confirm-separate-project')) {
  console.error(`Uso: node limits_probe.js --project <id-de-pruebas> --i-confirm-separate-project\n` +
    `Rechazado: hace falta un proyecto distinto de ${PROD} y la confirmación explícita.`);
  process.exit(2);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS || !process.env.LIMITS_API_KEY) {
  console.error('Faltan GOOGLE_APPLICATION_CREDENTIALS y/o LIMITS_API_KEY del proyecto de pruebas.');
  process.exit(2);
}

admin.initializeApp({ projectId });
const adb = admin.firestore();
const ts = () => admin.firestore.Timestamp.now();
const seeded = [];
const put = async (path, data) => { seeded.push(path); await adb.doc(path).set(data); };

async function clientFor(uid) {
  const app = initializeApp({ apiKey: process.env.LIMITS_API_KEY, projectId, authDomain: `${projectId}.firebaseapp.com` }, `probe-${uid}-${Date.now()}`);
  await signInWithCustomToken(getAuth(app), await admin.auth().createCustomToken(uid, { email_verified: true }));
  return getFirestore(app);
}

const move = (uid, insumo, delta, result, extra) => ({ insumoId: insumo, insumoNombre: `Insumo ${insumo}`, tipo: 'compra', delta,
  stockResultante: result, motivo: '', creadoPor: uid, creadoPorNombre: 'Admin sonda', creadoEn: serverTimestamp(), ...extra });

async function seedSupplies(n) {
  for (let i = 1; i <= n; i++) {
    await put(`insumos/s${i}`, { nombre: `Insumo s${i}`, unidad: 'kg', stock: 1000, stockMinimo: 0, activo: true, creadoEn: ts(), actualizadoEn: ts() });
    await put(`costosInsumos/s${i}`, { costoUnitario: 50, actualizadoEn: ts(), actualizadoPor: 'admin' });
  }
}

async function receive(lines, id) {
  const d = await clientFor('admin');
  const ls = Array.from({ length: lines }, (_, i) => ({ insumoId: `s${i + 1}`, nombre: `Insumo s${i + 1}`, cantidad: 1000, costoUnitario: 100, subtotal: 100 }));
  await put(`compras/${id}`, { proveedorId: 'p1', proveedorNombre: 'Proveedor sonda', lineas: ls, estado: 'pendiente',
    creadoPor: 'admin', creadoPorNombre: 'Admin sonda', creadoEn: ts() });
  const b = writeBatch(d);
  b.update(doc(d, 'compras', id), { estado: 'recibida', recibidoPor: 'admin', recibidoPorNombre: 'Admin sonda', recibidoEn: serverTimestamp() });
  ls.forEach((l, n) => {
    b.set(doc(d, 'movimientosInventario', `${id}_${n}`), move('admin', l.insumoId, 1000, 2000, { compraId: id, linea: n }));
    b.update(doc(d, 'insumos', l.insumoId), { stock: 2000, ultimoMovimiento: `${id}_${n}`, actualizadoEn: serverTimestamp() });
    b.set(doc(d, 'costosInsumos', l.insumoId), { costoUnitario: 100, actualizadoEn: serverTimestamp(), actualizadoPor: 'admin' });
  });
  seeded.push(...ls.map((_, n) => `movimientosInventario/${id}_${n}`));
  await b.commit();
}

async function delivery() {
  const d = await clientFor('w1');
  await put('utensilios/u1', { nombre: 'Bandeja', disponible: 10, enUso: 0, stockMinimo: 0, activo: true, versionCosto: 0,
    ultimaAuditoriaId: 'seed', creadoEn: ts(), actualizadoEn: ts() });
  const b = writeBatch(d);
  b.set(doc(d, 'movimientosUtensilios', 'probe1'), { utensilioId: 'u1', utensilioNombre: 'Bandeja', tipo: 'entrega', cantidad: 2,
    deltaDisponible: -2, deltaEnUso: 2, disponibleResultante: 8, enUsoResultante: 2, meseroId: 'w1', meseroNombre: 'Mesero sonda',
    versionCosto: 0, motivo: '', creadoPor: 'w1', creadoPorNombre: 'Mesero sonda', creadoEn: serverTimestamp() });
  b.update(doc(d, 'utensilios', 'u1'), { disponible: 8, enUso: 2, ultimoMovimiento: 'probe1', actualizadoEn: serverTimestamp() });
  b.set(doc(d, 'asignacionesUtensilios', 'u1_w1'), { utensilioId: 'u1', meseroId: 'w1', meseroNombre: 'Mesero sonda', cantidad: 2,
    ultimoMovimiento: 'probe1', actualizadoEn: serverTimestamp() });
  seeded.push('movimientosUtensilios/probe1', 'asignacionesUtensilios/u1_w1');
  await b.commit();
}

/** Fase 8B: Cocina marca «Listo» un pedido y descuenta [n] insumos en un lote. */
async function kitchenReady(n, order) {
  const d = await clientFor('cocina1');
  await put('pedidos/' + order, { mesaId: '1', meseroId: 'w1', meseroNombre: 'Mesero sonda', estado: 'registrado', revision: 2,
    cantidadDetalles: 1, detalleModificado: '', estadoCocina: 'preparando', creadoEn: ts(), actualizadoEn: ts(),
    registradoEn: ts(), preparandoEn: ts(), cocinaPor: 'cocina1' });
  const b = writeBatch(d);
  b.set(doc(d, 'descuentosInventario', order), { insumos: n, platosSinReceta: 0, insumosOmitidos: 0, creadoPor: 'cocina1',
    creadoPorNombre: 'Cocina sonda', creadoEn: serverTimestamp() });
  for (let i = 0; i < n; i++) {
    const id = 's' + (i + 1);
    const mid = order + '_' + i;
    b.set(doc(d, 'movimientosInventario', mid), { insumoId: id, insumoNombre: 'Insumo ' + id, tipo: 'consumo', delta: -10,
      stockResultante: 990, motivo: '', pedidoId: order, linea: i, creadoPor: 'cocina1', creadoPorNombre: 'Cocina sonda', creadoEn: serverTimestamp() });
    b.update(doc(d, 'insumos', id), { stock: 990, ultimoMovimiento: mid, actualizadoEn: serverTimestamp() });
    seeded.push('movimientosInventario/' + mid);
  }
  b.update(doc(d, 'pedidos', order), { estadoCocina: 'listo', listoEn: serverTimestamp(), revision: 3, actualizadoEn: serverTimestamp() });
  seeded.push('descuentosInventario/' + order);
  await b.commit();
}

const results = [];
async function probe(name, expectOk, fn) {
  let ok; let detail = '';
  try { await fn(); ok = true; } catch (e) { ok = false; detail = e.code || e.message; }
  results.push({ prueba: name, esperado: expectOk ? 'aceptada' : 'rechazada', real: ok ? 'aceptada' : `rechazada (${detail})`, correcto: ok === expectOk });
}

(async () => {
  await put('usuarios/admin', { rol: 'admin', nombre: 'Admin sonda', activo: true });
  await put('usuarios/w1', { rol: 'mesero', nombre: 'Mesero sonda', activo: true });
  await put('estadoAsistencia/w1', { abierta: true, asistenciaId: 'aw1' });
  await put('usuarios/cocina1', { rol: 'cocina', nombre: 'Cocina sonda', activo: true });
  await put('estadoAsistencia/cocina1', { abierta: true, asistenciaId: 'ac1' });
  await put('proveedores/p1', { nombre: 'Proveedor sonda', ruc: '', telefono: '', contacto: '', activo: true, creadoEn: ts(), actualizadoEn: ts() });
  await seedSupplies(9);
  await probe('Compra de 5 líneas (18 accesos)', true, () => receive(5, 'c5'));
  await probe('Compra de 6 líneas (21 accesos)', false, () => receive(6, 'c6'));
  await probe('Entrega de utensilios (6 accesos)', true, delivery);
  await probe('Fase 8B: «Listo» con 8 insumos (20 accesos)', true, () => kitchenReady(8, 'o8'));
  await probe('Fase 8B: «Listo» con 9 insumos (rechazada por regla de máximo 8)', false, () => kitchenReady(9, 'o9'));
  console.table(results);
  if (!args.includes('--keep')) {
    for (const p of [...new Set(seeded)]) await adb.doc(p).delete().catch(() => {});
    console.log('Datos de la sonda eliminados del proyecto de pruebas.');
  }
  process.exit(results.every((r) => r.correcto) ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
