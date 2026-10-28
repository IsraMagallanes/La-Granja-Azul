// Pruebas de firestore.rules. Se ejecutan con: npm run test:rules (requiere Java
// para el emulador de Firestore).
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection } = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-la-granja-azul',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':')[0],
      port: Number((process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':')[1]),
    },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const base = { email: 'x@granja.pe', nombre: 'X' };
    await setDoc(doc(db, 'usuarios/super'), { ...base, rol: 'superadmin', activo: true });
    await setDoc(doc(db, 'usuarios/admin'), { ...base, rol: 'admin', activo: true });
    for (const rol of ['mesero', 'cocina', 'cajero', 'almacen']) {
      await setDoc(doc(db, `usuarios/${rol}`), { ...base, rol, activo: true });
    }
    await setDoc(doc(db, 'usuarios/inactivo'), { ...base, rol: 'admin', activo: false });
    await setDoc(doc(db, 'categorias/aves'), { nombre: 'Aves', activo: true });
    await setDoc(doc(db, 'carta/plato1'), dish);
  });
});

const as = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const dish = { nombre: 'Pollo', descripcion: 'A la brasa', categoriaId: 'aves', precio: 25.50, imagenUrl: 'https://example.com/pollo.jpg', disponible: true };

test('anónimo no lee perfiles', () =>
  assertFails(getDoc(doc(anon(), 'usuarios/mesero'))));

test('usuario lee su propio perfil', () =>
  assertSucceeds(getDoc(doc(as('mesero'), 'usuarios/mesero'))));

test('usuario inactivo aún puede leer su perfil', () =>
  assertSucceeds(getDoc(doc(as('inactivo'), 'usuarios/inactivo'))));

test('mesero no lee el perfil de otro', () =>
  assertFails(getDoc(doc(as('mesero'), 'usuarios/admin'))));

test('mesero no lista usuarios', () =>
  assertFails(getDocs(collection(as('mesero'), 'usuarios'))));

test('admin activo lista usuarios', () =>
  assertSucceeds(getDocs(collection(as('admin'), 'usuarios'))));

test('admin inactivo no lista usuarios', () =>
  assertFails(getDocs(collection(as('inactivo'), 'usuarios'))));

test('nadie puede cambiar su propio rol', async () => {
  await assertFails(updateDoc(doc(as('mesero'), 'usuarios/mesero'), { rol: 'superadmin' }));
  await assertFails(updateDoc(doc(as('admin'), 'usuarios/admin'), { rol: 'superadmin' }));
  await assertFails(updateDoc(doc(as('super'), 'usuarios/super'), { rol: 'admin' }));
});

test('no se pueden crear superadmins desde el cliente', async () => {
  await assertFails(
    setDoc(doc(as('nuevo'), 'usuarios/nuevo'), { email: 'n@g.pe', nombre: 'N', rol: 'superadmin', activo: true }),
  );
  await assertFails(
    setDoc(doc(as('super'), 'usuarios/otro'), { email: 'o@g.pe', nombre: 'O', rol: 'superadmin', activo: true }),
  );
});

test('no se pueden borrar usuarios desde el cliente', () =>
  assertFails(deleteDoc(doc(as('super'), 'usuarios/mesero'))));

test('la carta es de lectura pública', () =>
  assertSucceeds(getDoc(doc(anon(), 'carta/plato1'))));

test('solo la administración edita la carta', async () => {
  await assertFails(setDoc(doc(anon(), 'carta/plato2'), dish));
  await assertFails(setDoc(doc(as('mesero'), 'carta/plato2'), dish));
  await assertSucceeds(setDoc(doc(as('admin'), 'carta/plato2'), dish));
});

test('colecciones no declaradas están bloqueadas', async () => {
  await assertFails(getDoc(doc(as('super'), 'secretos/x')));
  await assertFails(setDoc(doc(as('super'), 'secretos/x'), { a: 1 }));
});

for (const uid of ['super', 'admin']) {
  test(`${uid} crea y edita categorías y platos válidos`, async () => {
    const db = as(uid);
    await assertSucceeds(setDoc(doc(db, 'categorias/nueva'), { nombre: 'Nueva', activo: true }));
    await assertSucceeds(updateDoc(doc(db, 'categorias/nueva'), { nombre: 'Renombrada' }));
    await assertSucceeds(setDoc(doc(db, 'carta/nuevo'), { ...dish, categoriaId: 'nueva' }));
    await assertSucceeds(updateDoc(doc(db, 'carta/nuevo'), { precio: 30, disponible: false }));
    await assertFails(deleteDoc(doc(db, 'categorias/nueva')));
    await assertFails(deleteDoc(doc(db, 'carta/nuevo')));
  });
}
test('categorías públicas y escrituras restringidas incluso con datos válidos', async () => {
  await assertSucceeds(getDocs(collection(anon(), 'categorias')));
  for (const db of [anon(), as('mesero'), as('inactivo')]) {
    await assertFails(setDoc(doc(db, 'categorias/x'), { nombre: 'X', activo: true }));
    await assertFails(setDoc(doc(db, 'carta/x'), dish));
    await assertFails(updateDoc(doc(db, 'categorias/aves'), { activo: false }));
  }
});
test('valida campos y rechaza platos sin categoría existente', async () => {
  const db = as('admin');
  for (const patch of [{ precio: 0 }, { precio: -1 }, { precio: '25' }, { nombre: '' },
    { nombre: '   ' }, { descripcion: '' }, { categoriaId: 'no-existe' },
    { imagenUrl: 'data:image/png;base64,abcd' }, { imagenUrl: 'http://example.com/a.jpg' },
    { disponible: 'si' }, { extra: true }]) {
    await assertFails(setDoc(doc(db, 'carta/invalido'), { ...dish, ...patch }));
  }
  await assertFails(setDoc(doc(db, 'carta/incompleto'), { nombre: 'Pollo' }));
  for (const data of [{ nombre: '', activo: true }, { nombre: '  ', activo: true },
    { nombre: 'A', activo: 'si' }, { nombre: 'A', activo: true, extra: 1 }]) {
    await assertFails(setDoc(doc(db, 'categorias/invalida'), data));
  }
});
test('desactivar conserva referencias y permite reactivar sin huérfanos', async () => {
  const db = as('admin');
  await assertSucceeds(updateDoc(doc(db, 'categorias/aves'), { activo: false }));
  await assertSucceeds(getDoc(doc(anon(), 'carta/plato1')));
  await assertSucceeds(updateDoc(doc(db, 'carta/plato1'), { precio: 28 }));
  await assertFails(deleteDoc(doc(db, 'categorias/aves')));
  await assertSucceeds(updateDoc(doc(db, 'categorias/aves'), { activo: true }));
});

// Ambas pantallas usan listeners de colección completa, no lecturas de un solo documento.
test('consultas de carta y categorías permitidas sin sesión y con cualquier rol', async () => {
  for (const db of [anon(), ...['admin', 'super', 'mesero', 'cocina', 'cajero', 'almacen', 'inactivo'].map(as)]) {
    await assertSucceeds(getDocs(collection(db, 'carta')));
    await assertSucceeds(getDocs(collection(db, 'categorias')));
  }
});
test('los roles operativos no pueden gestionar ninguna colección de la carta', async () => {
  for (const uid of ['mesero', 'cocina', 'cajero', 'almacen', 'inactivo']) {
    const db = as(uid);
    await assertFails(setDoc(doc(db, 'carta/x'), dish));
    await assertFails(updateDoc(doc(db, 'carta/plato1'), { disponible: false }));
    await assertFails(setDoc(doc(db, 'categorias/x'), { nombre: 'X', activo: true }));
    await assertFails(updateDoc(doc(db, 'categorias/aves'), { activo: false }));
  }
});
test('regresión: reglas anteriores bloquean categorías incluso para un administrador activo', async () => {
  const legacy = await initializeTestEnvironment({
    projectId: 'demo-la-granja-azul-legacy',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, 'fixtures', 'firestore.pre_phase4.rules'), 'utf8'),
      host: (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':')[0],
      port: Number((process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180').split(':')[1]),
    },
  });
  try {
    await legacy.withSecurityRulesDisabled(async ctx => {
      await setDoc(doc(ctx.firestore(), 'usuarios/admin'), { rol: 'admin', activo: true });
    });
    for (const db of [legacy.unauthenticatedContext().firestore(), legacy.authenticatedContext('admin').firestore()]) {
      await assertSucceeds(getDocs(collection(db, 'carta')));
      await assertFails(getDocs(collection(db, 'categorias')));
    }
  } finally {
    await legacy.clearFirestore();
    await legacy.cleanup();
  }
});
