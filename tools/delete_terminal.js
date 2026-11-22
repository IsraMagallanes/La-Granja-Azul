#!/usr/bin/env node
/**
 * Elimina DEFINITIVAMENTE una terminal de asistencia ya inhabilitada: su cuenta
 * de Authentication y sus documentos operativos. Conserva las asistencias y la
 * auditoría. Se ejecuta solo desde el equipo del propietario (Admin SDK); la
 * app no puede hacerlo.
 *
 * Credenciales: clave de cuenta de servicio indicada en la variable de entorno
 * GOOGLE_APPLICATION_CREDENTIALS (ruta fuera del repositorio). El script solo
 * lee `project_id` para comprobar el proyecto; nunca imprime ni copia la clave.
 *
 * Uso (PowerShell):
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node delete_terminal.js --pendientes       # lista las solicitudes de la app
 *   node delete_terminal.js <uid>              # simulación: no cambia nada
 *   node delete_terminal.js <uid> --execute    # elimina, tras confirmar
 *
 * Flujo: el Superadmin solicita la eliminación en la app (Terminales →
 * Solicitar eliminación definitiva; queda auditada) y aquí se procesa. Sin
 * solicitud el script se niega, salvo con --sin-solicitud (uso excepcional).
 */
const fs = require('node:fs');
const readline = require('node:readline');
const admin = require('firebase-admin');
const { State, TerminalDeletionError, assertValidUid, execute, inspect, listPending } =
  require('./lib/terminal_deletion');

const EXPECTED_PROJECT = 'la-granja-azul-app';

function fail(message) {
  console.error(message);
  process.exit(1);
}

function projectIdOfKey(keyPath) {
  try {
    return JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id;
  } catch {
    return undefined;
  }
}

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function printReport(r, project, mode) {
  const si = (v) => (v ? 'sí' : 'no existe');
  console.log(`\nProyecto : ${project}`);
  console.log(`Modo     : ${mode}`);
  console.log(`UID      : ${r.uid}`);
  console.log(`Terminal : ${r.terminal ? `"${r.terminal.nombre}" (${r.terminal.activo === false ? 'inhabilitada' : 'ACTIVA'})` : 'sin documento terminales/{uid}'}`);
  console.log(`Correo   : ${r.auth ? r.auth.email : 'la cuenta de Authentication ya no existe'}`);
  console.log(`Solicitud: ${r.solicitud ? 'hecha desde la app' : 'no hay solicitud de la app'}`);
  console.log(`Estado   : ${r.state}`);
  console.log('\nSe CONSERVAN (no se tocan):');
  console.log(`  asistencias de esta terminal : ${r.conservar.asistencias}`);
  console.log(`  registros de auditoría       : ${r.conservar.auditoria} (se añadirá 1 de la eliminación)`);
  console.log('\nSe ELIMINARÁN:');
  console.log(`  cuenta de Authentication : ${r.eliminar.cuentaAuth ? 'sí' : 'ya eliminada'}`);
  console.log(`  terminales/{uid}         : ${si(r.eliminar.terminales)}`);
  console.log(`  terminalClaves/{uid}     : ${si(r.eliminar.terminalClaves)}`);
  console.log(`  terminalPruebas/{uid}    : ${si(r.eliminar.terminalPruebas)}`);
  console.log(`  solicitud de la app      : ${si(r.eliminar.solicitud)}`);
  console.log(`  qrTokens de la terminal  : ${r.eliminar.qrTokens} (temporales)`);
  if (r.blockers.length) {
    console.log('\nBLOQUEADO:');
    r.blockers.forEach((b) => console.log(`  - ${b}`));
  }
  if (r.state === State.resume) {
    console.log('\nLa cuenta de Authentication ya no existe pero quedan documentos: una ' +
      'ejecución anterior se interrumpió. Se completará la limpieza.');
  }
}

async function main() {
  const args = process.argv.slice(2);
  const run = args.includes('--execute');
  const pendingMode = args.includes('--pendientes');
  const requireRequest = !args.includes('--sin-solicitud');
  const uid = args.find((a) => !a.startsWith('--'));
  const known = ['--execute', '--pendientes', '--sin-solicitud'];
  const unknown = args.filter((a) => a.startsWith('--') && !known.includes(a));
  if (unknown.length || (pendingMode ? Boolean(uid) || run : !uid)) {
    fail('Uso: node delete_terminal.js --pendientes\n' +
      '     node delete_terminal.js <uid> [--execute] [--sin-solicitud]');
  }
  if (!pendingMode) {
    try {
      assertValidUid(uid);
    } catch (e) {
      fail(e.message);
    }
  }

  const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
  if (emulated) {
    console.log('AVISO: variables de emulador detectadas; no se usará producción.');
  } else {
    const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    if (!keyPath || !fs.existsSync(keyPath)) {
      fail('Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la clave de servicio.');
    }
    if (projectIdOfKey(keyPath) !== EXPECTED_PROJECT) {
      fail(`La clave no pertenece al proyecto ${EXPECTED_PROJECT}. Abortando.`);
    }
  }

  admin.initializeApp(
    emulated
      ? { projectId: EXPECTED_PROJECT }
      : { credential: admin.credential.applicationDefault(), projectId: EXPECTED_PROJECT });
  const auth = admin.auth();
  const db = admin.firestore();

  if (pendingMode) {
    const pending = await listPending({ db });
    if (!pending.length) {
      console.log('No hay solicitudes de eliminación pendientes.');
      return;
    }
    console.log(`Solicitudes pendientes (${pending.length}):`);
    for (const p of pending) {
      console.log(`  ${p.uid}  "${p.nombre}"  ${p.solicitadoEn ? p.solicitadoEn.toISOString() : ''}`);
    }
    console.log('\nSimular una: node delete_terminal.js <uid>');
    return;
  }

  const report = await inspect({ auth, db, uid, requireRequest });
  printReport(report, EXPECTED_PROJECT, run ? 'EJECUCIÓN REAL' : 'SIMULACIÓN (no se cambia nada)');

  if (report.state === State.blocked) fail('\nNo se puede continuar.');
  if (report.state === State.done) {
    console.log('\nNo queda nada que eliminar para este UID.');
    return;
  }
  if (!run) {
    console.log('\nSimulación terminada. Para eliminar: añade --execute.');
    return;
  }

  if (!process.stdin.isTTY) fail('\nLa confirmación requiere una terminal interactiva.');
  console.log('\nEsta acción es IRREVERSIBLE.');
  if ((await ask(`Escribe el ID del proyecto (${EXPECTED_PROJECT}): `)) !== EXPECTED_PROJECT) {
    fail('El ID del proyecto no coincide. Nada se eliminó.');
  }
  if ((await ask('Escribe el UID de la terminal: ')) !== uid) {
    fail('El UID no coincide. Nada se eliminó.');
  }

  try {
    const { progress } = await execute({
      auth, db, uid, FieldValue: admin.firestore.FieldValue, requireRequest,
    });
    console.log('\nTerminal eliminada por completo.');
    console.log(`  cuenta de Authentication eliminada : ${progress.cuentaAuth}`);
    console.log(`  qrTokens eliminados                : ${progress.qrTokens}`);
    console.log(`  documentos operativos eliminados   : ${progress.documentos}`);
    console.log(`  asistencias conservadas            : ${report.conservar.asistencias}`);
  } catch (e) {
    if (e instanceof TerminalDeletionError) {
      console.error(`\nERROR: ${e.message}`);
      console.error('Estado real tras el fallo:');
      console.error(`  cuenta de Authentication eliminada : ${e.progress.cuentaAuth}`);
      console.error(`  qrTokens eliminados                : ${e.progress.qrTokens}`);
      console.error(`  documentos operativos eliminados   : ${e.progress.documentos}`);
      console.error('La operación NO está completa. Vuelve a ejecutar el mismo comando ' +
        'para terminarla (es seguro repetirlo).');
      process.exit(2);
    }
    throw e;
  }
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
