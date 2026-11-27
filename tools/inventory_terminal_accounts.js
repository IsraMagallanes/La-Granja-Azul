#!/usr/bin/env node
/**
 * SOLO LECTURA. Inventario de las cuentas creadas exclusivamente para las
 * antiguas terminales de asistencia. No modifica Authentication ni Firestore.
 *
 * Para cada candidata aplica los cuatro criterios (tools/lib/terminal_criteria.js)
 * y emite un veredicto: TERMINAL EXCLUSIVA, EXCLUIDA (con motivo) o SIN CUENTA
 * AUTH. Los correos se muestran enmascarados; el UID se muestra completo porque
 * es el dato que usa `delete_terminal.js`. Incluye un resumen de los qrTokens.
 *
 * Credenciales: clave de cuenta de servicio en GOOGLE_APPLICATION_CREDENTIALS
 * (ruta fuera del repositorio); solo se lee `project_id`.
 *
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node inventory_terminal_accounts.js          # informe en texto
 *   node inventory_terminal_accounts.js --json   # mismo contenido en JSON
 */
const fs = require('node:fs');
const admin = require('firebase-admin');
const { collectInventory, formatReport } = require('./lib/terminal_inventory');

const EXPECTED_PROJECT = 'la-granja-azul-app';

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function main() {
  const args = process.argv.slice(2);
  const unknown = args.filter((a) => a !== '--json');
  if (unknown.length) fail('Uso: node inventory_terminal_accounts.js [--json]');

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

  const inventory = await collectInventory({ auth: admin.auth(), db: admin.firestore() });
  console.log(args.includes('--json')
    ? JSON.stringify(inventory, null, 2)
    : formatReport(inventory, EXPECTED_PROJECT));
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
