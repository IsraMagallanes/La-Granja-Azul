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
    projectId: 'la-granja-azul-app',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
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
    await setDoc(doc(db, 'usuarios/mesero'), { ...base, rol: 'mesero', activo: true });
    await setDoc(doc(db, 'usuarios/inactivo'), { ...base, rol: 'admin', activo: false });
    await setDoc(doc(db, 'carta/plato1'), { nombre: 'Pollo' });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

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
  await assertFails(setDoc(doc(anon(), 'carta/plato2'), { nombre: 'a' }));
  await assertFails(setDoc(doc(as('mesero'), 'carta/plato2'), { nombre: 'a' }));
  await assertSucceeds(setDoc(doc(as('admin'), 'carta/plato2'), { nombre: 'a' }));
});

test('colecciones no declaradas están bloqueadas', async () => {
  await assertFails(getDoc(doc(as('super'), 'secretos/x')));
  await assertFails(setDoc(doc(as('super'), 'secretos/x'), { a: 1 }));
});
