#!/usr/bin/env node
/**
 * SIMULACIÓN de la purga del sistema antiguo de terminales. SOLO LECTURA y único
 * modo existente: no hay opción para eliminar ni modificar nada. Verifica los
 * elementos autorizados (3 cuentas, terminales, terminalPruebas, 8 qrTokens y
 * 21 registros de auditoría) y escribe el informe en tools/informes/.
 *
 * Credenciales: GOOGLE_APPLICATION_CREDENTIALS (ruta fuera del repositorio);
 * solo se lee `project_id`, el contenido nunca se muestra.
 *
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node purge_terminals_dryrun.js
 */
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { collectPurgePlan, formatReport } = require('./lib/terminal_purge_plan');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const REPORT_DIR = path.join(__dirname, 'informes');

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function main() {
  if (process.argv.length > 2) fail('Uso: node purge_terminals_dryrun.js (sin argumentos; solo simulación)');

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

  const plan = await collectPurgePlan({ auth: admin.auth(), db: admin.firestore() });
  const report = formatReport(plan, EXPECTED_PROJECT);

  fs.mkdirSync(REPORT_DIR, { recursive: true });
  const file = path.join(REPORT_DIR, 'purga_terminales_simulacion.txt');
  fs.writeFileSync(file, `${report}\n`, 'utf8');
  console.log(report);
  console.log(`\nInforme guardado en ${path.relative(process.cwd(), file)}`);
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
