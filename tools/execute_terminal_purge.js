#!/usr/bin/env node
/**
 * PURGA REAL y controlada del sistema antiguo de terminales (38 elementos
 * autorizados por el propietario el 2026-11-27). IRREVERSIBLE salvo por el
 * respaldo local. Exige la ruta del respaldo y una confirmación literal.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node execute_terminal_purge.js --backup backups\purga_terminales_<fecha> --confirmar ELIMINAR-38
 *
 * Antes de eliminar: verifica el respaldo (SHA-256) y vuelve a consultar
 * Firebase; ante cualquier diferencia aborta sin borrar nada. Tras eliminar,
 * comprueba los resultados y escribe tools/informes/purga_terminales_resultado.txt.
 */
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { executePurge, verifyAfter, EXPECTED_TOTAL } = require('./lib/terminal_purge_exec');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const CONFIRMATION = 'ELIMINAR-38';

function fail(m) {
  console.error(m);
  process.exit(1);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!['--backup', '--confirmar'].includes(argv[i]) || argv[i + 1] === undefined) {
      fail('Uso: node execute_terminal_purge.js --backup <carpeta> --confirmar ELIMINAR-38');
    }
    out[argv[i].slice(2)] = argv[i + 1];
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.confirmar !== CONFIRMATION || !args.backup) {
    fail(`Falta --backup <carpeta> o --confirmar ${CONFIRMATION}. No se eliminó nada.`);
  }
  const backupDir = path.resolve(args.backup);
  if (!fs.existsSync(backupDir)) fail(`No existe el respaldo ${backupDir}. No se eliminó nada.`);

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
  if (project !== EXPECTED_PROJECT) fail(`La clave no pertenece al proyecto ${EXPECTED_PROJECT}. Abortando.`);
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: EXPECTED_PROJECT });
  const auth = admin.auth();
  const db = admin.firestore();

  const result = await executePurge({ auth, db, backupDir });
  const out = ['PURGA DEL SISTEMA ANTIGUO DE TERMINALES — RESULTADO', `Proyecto: ${EXPECTED_PROJECT}`,
    `Generado: ${new Date().toISOString()}`, `Respaldo: ${path.relative(process.cwd(), backupDir)}`, ''];
  if (result.abortado) {
    out.push('ABORTADA ANTES DE ELIMINAR (no se eliminó nada):', ...result.abortado.map((a) => `  • ${a}`));
    process.exitCode = 3;
  } else if (!result.ok) {
    out.push(`FALLO PARCIAL: ${result.error}`, `Eliminados (${result.eliminados.length}):`,
      ...result.eliminados.map((e) => `  - ${e}`), `Pendientes (${result.pendientes.length}):`,
      ...result.pendientes.map((e) => `  - ${e}`), 'Se detuvo sin continuar ni ampliar operaciones.');
    process.exitCode = 4;
  } else {
    const check = await verifyAfter({ auth, db, antes: result.antes, despues: result.despues });
    out.push(`Eliminados: ${result.eliminados.length} de ${EXPECTED_TOTAL}`, ...result.eliminados.map((e) => `  - ${e}`), '',
      'Conteos antes → después:',
      ...Object.keys(result.antes).map((k) => `  ${k}: ${result.antes[k]} → ${result.despues[k]}`), '',
      check.fallos.length ? `VERIFICACIÓN FALLIDA:\n${check.fallos.map((f) => `  • ${f}`).join('\n')}`
        : `Verificación en vivo correcta: los ${EXPECTED_TOTAL} elementos ya no existen y los datos protegidos están intactos.`);
    if (check.fallos.length) process.exitCode = 5;
  }
  const text = out.join('\n');
  fs.mkdirSync(path.join(__dirname, 'informes'), { recursive: true });
  fs.writeFileSync(path.join(__dirname, 'informes', 'purga_terminales_resultado.txt'), `${text}\n`, 'utf8');
  console.log(text);
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
