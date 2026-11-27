// Alineación matriz de permisos (Flutter) ↔ firestore.rules, y asistencia como
// condición de acceso operativo (Fase 2).
//
// `fixtures/permission_matrix.json` lo genera la prueba de Dart
// (`test/features/permission_service_test.dart`, con UPDATE_PERMISSION_MATRIX=1)
// desde `PermissionService`. Aquí cada celda rol × módulo × acción se ejecuta
// contra las reglas reales: lo que la matriz concede debe poder hacerse y lo
// que no, debe fallar.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction,
  serverTimestamp, Timestamp } = require('firebase/firestore');

const matrix = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixtures', 'permission_matrix.json'), 'utf8'));
const exempt = new Set(matrix.shiftExemptRoles);
const ROLE_UID = { superadmin: 'super', admin: 'admin', mesero: 'w1', cocina: 'k', cajero: 'cash' };
const UID_ROLE = Object.fromEntries(Object.entries(ROLE_UID).map(([r, u]) => [u, r]));
const QR = 'e'.repeat(32); // QR vigente generado por el Admin
const QR_SALIDA = 'f'.repeat(32);

let env;
const host = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':');
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-la-granja-azul-permisos', firestore: {
    host: host[0], port: Number(host[1]),
    rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8') } });
});
after(async () => { await env?.cleanup(); });

/** @param shift 'open' | 'closed' | 'none': estado de jornada de los roles no exentos. */
async function seed(shift = 'open') {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [rol, uid] of Object.entries(ROLE_UID)) {
      await setDoc(doc(db, 'usuarios', uid), { rol, nombre: `Usuario ${uid}`, nombres: `N${uid}`, activo: true });
      if (!exempt.has(rol) && shift !== 'none') {
        await setDoc(doc(db, 'estadoAsistencia', uid), { abierta: shift === 'open', asistenciaId: `a-${uid}` });
        if (shift === 'open') {
          await setDoc(doc(db, 'asistencias', `a-${uid}`), { uid, entrada: Timestamp.fromMillis(Date.now() - 3600_000),
            salida: null, origen: 'qr', tokenId: 'old', regularizada: false });
        }
      }
    }
    for (const id of [QR, QR_SALIDA]) {
      await setDoc(doc(db, 'qrTokens', id), { generadorUid: 'admin', generadorRol: 'admin', nombreMostrar: 'Nadmin',
        creadoEn: Timestamp.now() });
    }
    await setDoc(doc(db, 'usuarios', 'w2'), { rol: 'mesero', nombre: 'Usuario w2', nombres: 'Nw2', activo: true });
    await setDoc(doc(db, 'categorias/aves'), { nombre: 'Aves', activo: true });
    await setDoc(doc(db, 'mesas/1'), { numero: '1', capacidad: 4, activo: true, pedidoActivo: 'seed' });
    await setDoc(doc(db, 'mesas/2'), { numero: '2', capacidad: 4, activo: true, pedidoActivo: null });
    await setDoc(doc(db, 'pedidos/seed'), { mesaId: '1', meseroId: 'w1', meseroNombre: 'Usuario w1',
      estado: 'abierto', revision: 0, cantidadDetalles: 0, detalleModificado: '',
      creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(db, 'reservaciones/res1'), { mesaId: '2', cliente: 'Rosa Díaz', telefono: '987654321',
      personas: 3, fechaHora: Timestamp.fromDate(new Date(Date.now() + 86400000)), notas: '', estado: 'pendiente',
      creadoPor: 'w1', creadoPorNombre: 'Usuario w1', creadoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(db, 'pedidos/reg1'), { mesaId: '2', meseroId: 'w2', meseroNombre: 'Usuario w2',
      estado: 'registrado', estadoCocina: 'pendiente', revision: 1, cantidadDetalles: 1, detalleModificado: 'p',
      creadoEn: Timestamp.now(), registradoEn: Timestamp.now(), actualizadoEn: Timestamp.now() });
    await setDoc(doc(db, 'restricciones/12345678'), { estado: 'activa' });
  });
}
const as = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

// Operaciones representativas de cada celda de la matriz (módulo.acción).
const ops = {
  'staff.read': (d) => getDoc(doc(d, 'usuarios', 'w2')),
  'menu.create': (d) => setDoc(doc(d, 'categorias', 'postres'), { nombre: 'Postres', activo: true }),
  'menu.update': (d) => updateDoc(doc(d, 'categorias', 'aves'), { activo: false }),
  'tables.read': (d) => getDoc(doc(d, 'mesas', '1')),
  'tables.create': (d) => setDoc(doc(d, 'mesas', '9'),
    { numero: '9', capacidad: 4, activo: true, pedidoActivo: null }),
  'tables.update': (d) => updateDoc(doc(d, 'mesas', '1'), { capacidad: 8 }),
  'orders.read': (d) => getDoc(doc(d, 'pedidos', 'seed')),
  'orders.create': (d, uid) => runTransaction(d, async (tx) => {
    const table = doc(d, 'mesas', '2');
    if ((await tx.get(table)).data().pedidoActivo !== null) throw Error('mesa ocupada');
    tx.set(doc(d, 'pedidos', 'nuevo'), { mesaId: '2', meseroId: uid, meseroNombre: `Usuario ${uid}`,
      estado: 'abierto', revision: 0, cantidadDetalles: 0, detalleModificado: '',
      creadoEn: serverTimestamp(), actualizadoEn: serverTimestamp() });
    tx.update(table, { pedidoActivo: 'nuevo' });
  }),
  'orders.update': (d, uid) => runTransaction(d, async (tx) => {
    const ref = doc(d, 'pedidos', 'seed');
    const order = (await tx.get(ref)).data();
    tx.update(ref, { estado: 'cancelado', revision: order.revision + 1, actualizadoEn: serverTimestamp(),
      motivoCancelacion: 'Cliente se fue', canceladoPor: uid });
    tx.update(doc(d, 'mesas', '1'), { pedidoActivo: null });
  }),
  'kitchen.update': (d, uid) => runTransaction(d, async (tx) => {
    const ref = doc(d, 'pedidos', 'reg1');
    const order = (await tx.get(ref)).data();
    tx.update(ref, { estadoCocina: 'preparando', revision: order.revision + 1, actualizadoEn: serverTimestamp(),
      preparandoEn: serverTimestamp(), cocinaPor: uid });
  }),
  'reservations.read': (d) => getDoc(doc(d, 'reservaciones', 'res1')),
  'reservations.create': (d, uid) => setDoc(doc(d, 'reservaciones', 'nueva'), {
    mesaId: '2', cliente: 'Rosa Díaz', telefono: '987654321', personas: 3,
    fechaHora: Timestamp.fromDate(new Date(Date.now() + 86400000)), notas: '', estado: 'pendiente',
    creadoPor: uid, creadoPorNombre: `Usuario ${uid}`, creadoEn: serverTimestamp(), actualizadoEn: serverTimestamp() }),
  'reservations.update': (d) => updateDoc(doc(d, 'reservaciones', 'res1'),
    { estado: 'confirmada', actualizadoEn: serverTimestamp() }),
  'attendance.read': (d) => getDocs(collection(d, 'estadoAsistencia')),
  'selfAttendance.read': (d, uid) => getDoc(doc(d, 'estadoAsistencia', uid)),
  // Generar el QR: solo Superadmin, Admin y Cajero.
  'qrGenerate.create': (d, uid) => setDoc(doc(d, 'qrTokens', 'a'.repeat(32)),
    { generadorUid: uid, generadorRol: UID_ROLE[uid], nombreMostrar: `N${uid}`, creadoEn: serverTimestamp() }),
  // Escanear el QR (salida de la jornada abierta): solo Mesero, Cocina y Cajero.
  'qrScan.create': (d, uid) => {
    const batch = writeBatch(d);
    batch.update(doc(d, 'asistencias', `a-${uid}`), { salida: serverTimestamp(), salidaTokenId: QR_SALIDA });
    batch.set(doc(d, 'estadoAsistencia', uid), { abierta: false, asistenciaId: `a-${uid}`,
      actualizadoEn: serverTimestamp(), tokenId: QR_SALIDA });
    return batch.commit();
  },
  'cashier.read': (d) => getDocs(collection(d, 'pagos')),
  'cashier.create': (d, uid) => {
    const batch = writeBatch(d);
    const box = { montoInicial: 0, abiertaPor: uid, abiertaPorNombre: `Usuario ${uid}`, abiertaEn: serverTimestamp() };
    batch.set(doc(d, 'cajas', 'cx'), { estado: 'abierta', ...box });
    batch.set(doc(d, 'cajaActiva', 'actual'), { cajaId: 'cx', ...box });
    return batch.commit();
  },
  'supplies.read': (d) => getDocs(collection(d, 'insumos')),
  'supplies.create': (d) => setDoc(doc(d, 'insumos', 'nuevo'), { nombre: 'Aceite', unidad: 'l', stock: 0, stockMinimo: 0,
    activo: true, creadoEn: serverTimestamp(), actualizadoEn: serverTimestamp() }),
  // Costos de insumos: solo la administración (Cocina nunca los lee).
  'supplies.special': (d) => getDocs(collection(d, 'costosInsumos')),
  'purchasing.read': (d) => getDocs(collection(d, 'proveedores')),
  'purchasing.create': (d) => setDoc(doc(d, 'proveedores', 'nuevo'), { nombre: 'Nuevo SAC', ruc: '', telefono: '', contacto: '',
    activo: true, creadoEn: serverTimestamp(), actualizadoEn: serverTimestamp() }),
  'utensils.read': (d) => getDocs(collection(d, 'utensilios')),
  // Costos y valoración de utensilios: solo la administración (el Mesero nunca los lee).
  'utensils.special': (d) => getDocs(collection(d, 'costosUtensilios')),
  'restrictions.read': (d) => getDoc(doc(d, 'restricciones', '12345678')),
  'audit.read': (d) => getDocs(collection(d, 'auditoria')),
};

// Celdas sin operación aquí, con el motivo (la prueba falla si aparece una celda
// nueva sin clasificar, para que nadie la deje sin contrastar).
const COVERED_ELSEWHERE = {
  'staff.create': 'personal.rules.test.js (alta, jerarquía, duplicados)',
  'staff.update': 'personal.rules.test.js (edición, bajas, reactivación)',
  'staff.special': 'personal.rules.test.js (solo el Superadmin asigna administradores)',
  'kitchen.read': 'orders.rules.test.js (cocina y administración leen los pedidos; la caja también por orders.read)',
  'cashier.update': 'caja.rules.test.js (cobro, movimientos y cierre de caja)',
  'supplies.update': 'inventario.rules.test.js (stock con movimiento, recetas, costos)',
  'purchasing.update': 'inventario.rules.test.js (compras, recepción, proveedores)',
  'utensils.create': 'utensilios.rules.test.js (el Mesero registra movimientos; el catálogo es del Admin)',
  'utensils.update': 'utensilios.rules.test.js (catálogo con auditoría, existencias y asignaciones)',
  'attendance.update': 'asistencia.rules.test.js (horarios y regularización)',
  'selfAttendance.update': 'sin acción concedida',
  'restrictions.create': 'personal.rules.test.js (restricciones)',
  'restrictions.update': 'personal.rules.test.js (restricciones)',
};
const PUBLIC = { 'menu.read': 'la carta (carta y categorias) es de lectura pública' };
const NOT_ENFORCED = [
  'dashboard', 'roles', 'reports',
]; // sin colecciones propias todavía: solo se aplican en Flutter (rutas)

const cells = [];
for (const [module, actions] of Object.entries(matrix.modules)) {
  for (const [action, roles] of Object.entries(actions)) cells.push({ key: `${module}.${action}`, module, roles });
}

test('toda celda de la matriz está contrastada, delegada o declarada sin reglas', () => {
  const unclassified = cells
    .filter((c) => !ops[c.key] && !COVERED_ELSEWHERE[c.key] && !PUBLIC[c.key]
      && !NOT_ENFORCED.includes(c.module) && c.roles.length > 0)
    .map((c) => c.key);
  assert.deepEqual(unclassified, [], `celdas sin contrastar con las reglas: ${unclassified}`);
  const stale = Object.keys(ops).filter((k) => !cells.some((c) => c.key === k));
  assert.deepEqual(stale, [], `operaciones de prueba para celdas que ya no existen: ${stale}`);
});

test('los roles exentos de asistencia son exactamente superadmin y admin', () => {
  assert.deepEqual([...exempt].sort(), ['admin', 'superadmin']);
});

for (const cell of cells.filter((c) => ops[c.key])) {
  for (const role of Object.keys(ROLE_UID)) {
    const allowed = cell.roles.includes(role);
    test(`${cell.key}: ${role} ${allowed ? 'puede' : 'no puede'} (jornada abierta)`, async () => {
      await seed('open');
      const uid = ROLE_UID[role];
      const run = ops[cell.key](as(uid), uid);
      await (allowed ? assertSucceeds(run) : assertFails(run));
    });
  }
}

// --------------------------------------------------- Asistencia como condición
const OPERATIONAL = ['tables.read', 'orders.read', 'orders.create', 'orders.update',
  'reservations.read', 'reservations.create', 'reservations.update', 'kitchen.update',
  'cashier.read', 'cashier.create', 'supplies.read', 'supplies.create', 'purchasing.read', 'utensils.read'];

for (const shift of ['none', 'closed']) {
  for (const key of OPERATIONAL) {
    for (const role of Object.keys(ROLE_UID)) {
      const [module, action] = key.split('.');
      const hasPermission = matrix.modules[module][action].includes(role);
      if (!hasPermission) continue;
      const free = exempt.has(role);
      test(`${key}: ${role} ${free ? 'sigue pudiendo (exento)' : 'pierde acceso'} sin entrada (${shift === 'none' ? 'sin registro' : 'jornada cerrada'})`,
        async () => {
          await seed(shift);
          const uid = ROLE_UID[role];
          const run = ops[key](as(uid), uid);
          await (free ? assertSucceeds(run) : assertFails(run));
        });
    }
  }
}

test('sin entrada el personal conserva «Mi asistencia» y los generadores generan el QR sin jornada abierta', async () => {
  for (const shift of ['none', 'closed']) {
    for (const [role, uid] of Object.entries(ROLE_UID)) {
      await seed(shift);
      await assertSucceeds(ops['selfAttendance.read'](as(uid), uid));
      const generate = ops['qrGenerate.create'](as(uid), uid);
      await (matrix.modules.qrGenerate.create.includes(role) ? assertSucceeds(generate) : assertFails(generate));
    }
  }
});

test('registrar la salida cierra el acceso operativo al instante', async () => {
  await seed('open');
  const w1 = as('w1');
  await assertSucceeds(getDoc(doc(w1, 'pedidos', 'seed')));
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'estadoAsistencia', 'w1'), { abierta: false }));
  await assertFails(getDoc(doc(w1, 'pedidos', 'seed')));
  await assertFails(getDoc(doc(w1, 'mesas', '1')));
  // Y registrar la entrada de nuevo lo reabre.
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'estadoAsistencia', 'w1'), { abierta: true }));
  await assertSucceeds(getDoc(doc(w1, 'pedidos', 'seed')));
});

test('la jornada abierta de otro trabajador no concede acceso', async () => {
  await seed('closed');
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'estadoAsistencia', 'k'), { abierta: true }));
  await assertSucceeds(getDoc(doc(as('k'), 'pedidos', 'seed')));
  await assertFails(getDoc(doc(as('w1'), 'pedidos', 'seed')));
});

test('la jornada abierta no reemplaza al rol ni al perfil activo', async () => {
  await seed('open');
  // El cajero con jornada abierta sigue sin ver pedidos; cocina inactiva tampoco.
  await assertFails(getDocs(collection(as('cash'), 'insumos')));
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'usuarios', 'k'), { activo: false }));
  await assertFails(getDoc(doc(as('k'), 'pedidos', 'seed')));
});

test('un mesero con jornada abierta no puede crearse su propio estado de jornada', async () => {
  await seed('none');
  await assertFails(setDoc(doc(as('w1'), 'estadoAsistencia', 'w1'), { abierta: true, asistenciaId: 'x', actualizadoEn: serverTimestamp() }));
  await assertFails(getDoc(doc(as('w1'), 'pedidos', 'seed')));
});
