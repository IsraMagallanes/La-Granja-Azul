#!/usr/bin/env node
/**
 * Migra los costos de los insumos a la colección protegida `costosInsumos`
 * (solo Admin y Superadmin) y quita el campo `costoUnitario` de `insumos` y de
 * los movimientos de compra, para que Cocina deje de leer costos.
 *
 * NO se ejecuta automáticamente ni forma parte del despliegue: es una acción
 * manual del propietario, con su autorización expresa, desde su equipo (Admin
 * SDK). Lógica y garantías: tools/lib/supply_costs_migration.js.
 *
 * Credenciales: clave de cuenta de servicio en GOOGLE_APPLICATION_CREDENTIALS
 * (ruta fuera del repositorio); solo se lee `project_id`.
 *
 *   cd tools; npm install
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node migrate_supply_costs.js              # simulación: no cambia nada
 *   node migrate_supply_costs.js --execute    # migra, tras confirmar
 *
 * La simulación informa de conflictos (que bloquean la migración), de las copias
 * y limpiezas previstas y de las compras pendientes con más de 5 líneas.
 */
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');
const admin = require('firebase-admin');
const {
  MAX_PURCHASE_LINES, MigrationError, State, executeMigration, inspectMigration,
} = require('./lib/supply_costs_migration');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const CONFIRMATION = 'MIGRAR COSTOS';

function fail(message) {
  console.error(message);
  process.exit(1);
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

function printReport(r, mode) {
  const c = r.counts;
  console.log(`\nProyecto : ${EXPECTED_PROJECT}`);
  console.log(`Modo     : ${mode}`);
  console.log(`Estado   : ${r.state}`);
  console.log(`\nInsumos analizados                         : ${c.insumos}`);
  console.log(`Costos por copiar a costosInsumos          : ${c.aCopiar}`);
  console.log(`Costos ya copiados (idénticos)             : ${c.yaCopiados}`);
  console.log(`Insumos a los que se quitará costoUnitario : ${c.insumosALimpiar}`);
  console.log(`Movimientos de compra (se quita el campo)  : ${c.movimientosALimpiar}`);
  console.log('\nNo se tocará ningún otro campo ni documento (solo se añade 1 entrada de auditoría).');
  if (r.conflicts.length) {
    console.log(`\nCONFLICTOS (${r.conflicts.length}); bloquean la migración:`);
    r.conflicts.forEach((x) => console.log(`  - ${x}`));
  }
  if (r.oversizedPending.length) {
    console.log(`\nAVISO: compras PENDIENTES con más de ${MAX_PURCHASE_LINES} líneas ` +
      '(no podrían recibirse con las reglas nuevas; solo cancelarse o rehacerse):');
    r.oversizedPending.forEach((id) => console.log(`  - compras/${id}`));
  }
}

/** Copia de seguridad (JSON) de todo lo que la migración va a cambiar. */
function writeBackup(report) {
  const dir = path.join(__dirname, 'backups');
  fs.mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(dir, 'migrate_supply_costs_' + stamp + '.json');
  fs.writeFileSync(file, JSON.stringify({
    proyecto: EXPECTED_PROJECT,
    creadoEn: new Date().toISOString(),
    nota: 'Valores de costoUnitario que la migración quita. Para revertir: volver a escribir cada costo en su documento.',
    insumos: report.insumosToStrip.map((x) => ({ id: x.id, costoUnitario: x.cost })),
    movimientosCompra: report.movementsToStrip.map((x) => ({ id: x.id, costoUnitario: x.cost })),
    costosPorCopiar: report.toCopy,
  }, null, 2));
  return file;
}

async function main() {
  const args = process.argv.slice(2);
  const known = ['--execute'];
  if (args.some((a) => !known.includes(a))) fail('Uso: node migrate_supply_costs.js [--execute]');
  const run = args.includes('--execute');

  const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (emulated) {
    console.log('AVISO: variable de emulador detectada; no se usará producción.');
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
  const db = admin.firestore();

  const report = await inspectMigration({ db });
  printReport(report, run ? 'EJECUCIÓN REAL' : 'SIMULACIÓN (no se cambia nada)');
  if (report.state === State.blocked) fail('\nNo se puede continuar: resuelve los conflictos.');
  if (report.state === State.done) {
    console.log('\nNo queda nada que migrar.');
    return;
  }
  if (!run) {
    console.log('\nSimulación terminada. Para migrar: añade --execute.');
    return;
  }

  if (!process.stdin.isTTY) fail('\nLa confirmación requiere una terminal interactiva.');
  console.log('\nEsta acción modifica documentos históricos (quita un campo duplicado) y no se deshace sola.');
  if ((await ask(`Escribe el ID del proyecto (${EXPECTED_PROJECT}): `)) !== EXPECTED_PROJECT) {
    fail('El ID del proyecto no coincide. Nada se modificó.');
  }
  if ((await ask(`Escribe «${CONFIRMATION}»: `)) !== CONFIRMATION) {
    fail('La confirmación no coincide. Nada se modificó.');
  }

  console.log('\nCopia de seguridad escrita en: ' + writeBackup(report));
  try {
    const { progress } = await executeMigration({ db, FieldValue: admin.firestore.FieldValue });
    console.log('\nMigración completada.');
    console.log(`  costos copiados                 : ${progress.copiados}`);
    console.log(`  insumos sin costoUnitario       : ${progress.insumosLimpios}`);
    console.log(`  movimientos de compra limpiados : ${progress.movimientosLimpios}`);
  } catch (e) {
    if (e instanceof MigrationError) {
      console.error(`\nERROR: ${e.message}`);
      console.error('Estado real tras el fallo:');
      console.error(`  costos copiados                 : ${e.progress.copiados}`);
      console.error(`  insumos sin costoUnitario       : ${e.progress.insumosLimpios}`);
      console.error(`  movimientos de compra limpiados : ${e.progress.movimientosLimpios}`);
      console.error('La migración NO está completa. Vuelve a ejecutar el mismo comando ' +
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
