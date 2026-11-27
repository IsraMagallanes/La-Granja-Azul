#!/usr/bin/env node
/**
 * SOLO LECTURA. Inventario de los perfiles con rol Almacén (rol que se retirará
 * del sistema). No modifica usuarios, Authentication ni Firestore, y no reasigna
 * ni elimina nada: sirve para decidir, perfil por perfil, qué hacer.
 *
 * Muestra UID, nombres de pila, estado, fechas, jornada y cuántos registros
 * históricos referencian a cada perfil. NO muestra documento, celular,
 * apellidos ni el correo completo (sale enmascarado).
 *
 * Credenciales: clave de cuenta de servicio en GOOGLE_APPLICATION_CREDENTIALS
 * (ruta fuera del repositorio); solo se lee `project_id`.
 *
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node inventory_almacen_users.js          # informe en texto
 *   node inventory_almacen_users.js --json   # mismo contenido en JSON
 */
const fs = require('node:fs');
const admin = require('firebase-admin');
const { collectAlmacenInventory, formatReport } = require('./lib/almacen_inventory');

const EXPECTED_PROJECT = 'la-granja-azul-app';

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some((a) => a !== '--json')) fail('Uso: node inventory_almacen_users.js [--json]');

  const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
  if (emulated) {
    console.error('AVISO: variables de emulador detectadas; no se usará producción.');
  } else {
    const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (!keyPath || !fs.existsSync(keyPath)) {
      fail('Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la clave de servicio.');
    }
    let project;
    try {
      project = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
    } catch {
      project = undefined;
    }
    if (project !== EXPECTED_PROJECT) {
      fail(`La clave no pertenece al proyecto ${EXPECTED_PROJECT}. Abortando.`);
    }
  }

  admin.initializeApp(
    emulated
      ? { projectId: EXPECTED_PROJECT }
      : { credential: admin.credential.applicationDefault(), projectId: EXPECTED_PROJECT });

  const inventory = await collectAlmacenInventory({ auth: admin.auth(), db: admin.firestore() });
  console.log(args.includes('--json')
    ? JSON.stringify(inventory, null, 2)
    : formatReport(inventory, EXPECTED_PROJECT));
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
