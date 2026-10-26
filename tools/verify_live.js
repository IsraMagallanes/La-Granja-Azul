#!/usr/bin/env node
/**
 * Verificación en vivo contra el proyecto real: login con correo/contraseña y
 * reglas de Firestore desplegadas. Crea usuarios temporales (mesero, inactivo)
 * con contraseñas aleatorias y los elimina al terminar.
 *
 * Requiere GOOGLE_APPLICATION_CREDENTIALS y WEB_API_KEY (la apiKey web de
 * lib/firebase_options.dart). No imprime credenciales.
 */
const crypto = require('node:crypto');
const admin = require('firebase-admin');

const PROJECT = 'la-granja-azul-app';
const apiKey = process.env.WEB_API_KEY;
if (!apiKey || !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Faltan WEB_API_KEY y/o GOOGLE_APPLICATION_CREDENTIALS.');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT });
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

let failures = 0;
function check(name, ok) {
  console.log(`${ok ? 'OK  ' : 'FALLA'} ${name}`);
  if (!ok) failures++;
}

async function signIn(email, password) {
  const r = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await r.json();
  return r.ok ? body : { error: body.error?.message };
}

const call = (token, method, path, body) =>
  fetch(`${FS}/${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });

const str = (v) => ({ stringValue: v });

async function createStaff(role, activo, suffix) {
  const email = `verif-${suffix}-${Date.now()}@granja-test.invalid`;
  const password = crypto.randomBytes(12).toString('base64url');
  const user = await admin.auth().createUser({ email, password });
  await admin.firestore().collection('usuarios').doc(user.uid).set({
    email, nombre: `Verif ${role}`, rol: role, activo,
  });
  return { uid: user.uid, email, password };
}

async function main() {
  const created = [];
  try {
    const mesero = await createStaff('mesero', true, 'mesero');
    const inactivo = await createStaff('cajero', false, 'inactivo');
    created.push(mesero, inactivo);

    const bad = await signIn(mesero.email, 'incorrecta-123');
    check('login con contraseña incorrecta es rechazado', !!bad.error);

    const s = await signIn(mesero.email, mesero.password);
    check('login válido del mesero', !!s.idToken);

    const own = await call(s.idToken, 'GET', `usuarios/${mesero.uid}`);
    check('mesero lee su propio perfil', own.status === 200);

    const other = await call(s.idToken, 'GET', `usuarios/${inactivo.uid}`);
    check('mesero NO lee el perfil de otro', other.status === 403);

    const list = await call(s.idToken, 'GET', 'usuarios');
    check('mesero NO lista usuarios', list.status === 403);

    const escalate = await call(
      s.idToken, 'PATCH', `usuarios/${mesero.uid}?updateMask.fieldPaths=rol`,
      { fields: { rol: str('superadmin') } },
    );
    check('mesero NO puede cambiar su propio rol', escalate.status === 403);

    const selfCreate = await call(
      s.idToken, 'PATCH', `usuarios/nuevo-superadmin`,
      { fields: { rol: str('superadmin'), activo: { booleanValue: true } } },
    );
    check('mesero NO puede crear un superadmin', selfCreate.status === 403);

    const menuWrite = await call(
      s.idToken, 'PATCH', 'carta/prueba', { fields: { nombre: str('x') } },
    );
    check('mesero NO edita la carta', menuWrite.status === 403);

    const secret = await call(s.idToken, 'GET', 'otra_coleccion/x');
    check('colecciones no declaradas bloqueadas', secret.status === 403);

    const anonMenu = await fetch(`${FS}/carta`);
    check('carta legible sin sesión', anonMenu.status === 200);

    const anonUsers = await fetch(`${FS}/usuarios/${mesero.uid}`);
    check('perfiles NO legibles sin sesión', anonUsers.status === 403);

    const si = await signIn(inactivo.email, inactivo.password);
    const ownInactive = await call(si.idToken, 'GET', `usuarios/${inactivo.uid}`);
    const doc = await ownInactive.json();
    check(
      'usuario inactivo lee su perfil y ve activo=false',
      ownInactive.status === 200 && doc.fields?.activo?.booleanValue === false,
    );
  } finally {
    for (const u of created) {
      await admin.firestore().collection('usuarios').doc(u.uid).delete().catch(() => {});
      await admin.auth().deleteUser(u.uid).catch(() => {});
    }
  }
  console.log(failures === 0 ? '\nTodas las verificaciones pasaron.' : `\n${failures} verificaciones fallaron.`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
