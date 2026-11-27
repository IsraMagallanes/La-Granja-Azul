#!/usr/bin/env node
/**
 * Prepara la purga SIN EJECUTARLA: vuelve a consultar Firebase, compara con el
 * último informe, respalda en local los candidatos y escribe el informe previo
 * a la purga. SOLO LECTURA sobre Firebase; no existe modo de eliminación.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node prepare_purge_backup.js
 *
 * Salidas: tools/backups/purga_terminales_<fecha>/ (fuera de git; contiene
 * correos completos, tratar como confidencial) y
 * tools/informes/purga_terminales_previa.txt (sin datos sensibles).
 */
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { collectPurgePlan, formatReport } = require('./lib/terminal_purge_plan');
const { buildBackup, candidatesFromPlan, candidatesFromReport, sha256 } = require('./lib/terminal_purge_backup');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const REPORT_DIR = path.join(__dirname, 'informes');
const PREVIOUS = path.join(REPORT_DIR, 'purga_terminales_simulacion.txt');

function fail(m) {
  console.error(m);
  process.exit(1);
}

async function main() {
  if (process.argv.length > 2) fail('Uso: node prepare_purge_backup.js (sin argumentos)');
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

  const plan = await collectPurgePlan({ auth, db });
  const now = candidatesFromPlan(plan);
  const before = fs.existsSync(PREVIOUS) ? candidatesFromReport(fs.readFileSync(PREVIOUS, 'utf8')) : null;
  const cambios = [];
  if (before) {
    for (const x of before) if (!now.has(x)) cambios.push(`ya no es candidato: ${x}`);
    for (const x of now) if (!before.has(x)) cambios.push(`candidato nuevo, ausente en el informe anterior: ${x}`);
  } else {
    cambios.push('no hay informe anterior con el que comparar');
  }

  const backup = await buildBackup({ auth, db, plan });
  const stamp = plan.generado.replace(/[:.]/g, '-');
  const dir = path.join(__dirname, 'backups', `purga_terminales_${stamp}`);
  for (const f of backup.files) {
    const target = path.join(dir, f.file);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, f.content, 'utf8');
  }
  // Releer del disco y comprobar integridad.
  const corruptos = backup.files.filter(
    (f) => sha256(fs.readFileSync(path.join(dir, f.file), 'utf8')) !== f.sha256);
  const manifest = {
    generado: plan.generado,
    proyecto: EXPECTED_PROJECT,
    cuentasAuth: backup.accounts,
    documentos: backup.documents,
    faltantesAlRespaldar: backup.missing,
    archivos: backup.files.map((f) => ({ file: f.file, sha256: f.sha256 })),
  };
  fs.writeFileSync(path.join(dir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');

  const k = plan.conservados;
  const t = plan.totales;
  const extra = [
    '', '── Reverificación y respaldo previos a la purga ─────────',
    `Cambios frente al informe anterior: ${cambios.length ? '' : 'ninguno'}`,
    ...cambios.map((c) => `  • ${c}`),
    `Respaldo local: tools/backups/${path.basename(dir)} (${backup.files.length} archivos + manifest.json)`,
    `  cuentas de Authentication respaldadas: ${backup.accounts} | documentos Firestore respaldados: ${backup.documents}`,
    `  faltantes al respaldar: ${backup.missing.length ? backup.missing.join(', ') : 'ninguno'}`,
    `  integridad (SHA-256 releído de disco): ${corruptos.length ? `FALLA en ${corruptos.map((c) => c.file).join(', ')}` : 'correcta'}`,
    '  Authentication: no se guardan hash ni sal de contraseña; las cuentas no se podrían restaurar con la misma contraseña (las terminales antiguas ya no se usan).',
    'Se conservarán tras la purga:',
    `  asistencias: ${k.asistencias} de ${k.asistencias}`,
    `  perfiles en usuarios: ${k.usuarios} de ${k.usuarios} (cuentas normales sin tocar)`,
    `  qrTokens: ${k.qrTokensTotal - t.qrTokens} de ${k.qrTokensTotal} (incluye ${k.qrTokensSistemaNuevo} del sistema nuevo)`,
    `  auditoría: ${k.auditoriaTotal - t.auditoria} de ${k.auditoriaTotal} (las ajenas a terminales)`,
  ].join('\n');
  const report = `${formatReport(plan, EXPECTED_PROJECT)}\n${extra}`;
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  fs.writeFileSync(path.join(REPORT_DIR, 'purga_terminales_previa.txt'), `${report}\n`, 'utf8');
  console.log(report);
  if (corruptos.length || backup.missing.length) process.exitCode = 2;
}

main().catch((e) => {
  console.error(`Error inesperado: ${e.message}`);
  process.exit(1);
});
