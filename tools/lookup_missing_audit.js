#!/usr/bin/env node
/**
 * SOLO LECTURA. Busca en `auditoria` los dos registros que faltaban de la
 * autorización (ids de 19 caracteres, posible error de transcripción) por
 * acción + objetivo, y compara con los ids autorizados. No escribe nada.
 *
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
 *   node lookup_missing_audit.js
 */
const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');
const { AUTHORIZED } = require('./lib/terminal_purge_plan');

const EXPECTED_PROJECT = 'la-granja-azul-app';
const TARGETS = [
  { accion: 'revocar_terminal', objetivo: '29519GHJw0RHouh6yj4lcdQkIVg1', aprox: '2026-11-27T14:41Z' },
  { accion: 'restablecer_terminal', objetivo: 'WlEJWNwIvFRzULaO1hQ6vYxbTjF2', aprox: '2026-11-26T20:52Z' },
];
const INVALID = ['4IQETUcGGBoGOQ2K4md', 'gmf76Ifgkj2LJu9kSoB'];

function fail(m) { console.error(m); process.exit(1); }

async function main() {
  if (process.argv.length > 2) fail('Uso: node lookup_missing_audit.js (sin argumentos)');
  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath || !fs.existsSync(keyPath)) fail('Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la clave de servicio.');
  let project;
  try { project = JSON.parse(fs.readFileSync(keyPath, 'utf8')).project_id; } catch { project = undefined; }
  if (project !== EXPECTED_PROJECT) fail(`La clave no pertenece al proyecto ${EXPECTED_PROJECT}. Abortando.`);
  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: EXPECTED_PROJECT });
  const db = admin.firestore();

  const out = [`Búsqueda de auditorías faltantes — proyecto ${EXPECTED_PROJECT} — SOLO LECTURA`,
    `Ids no encontrados de la autorización original: ${INVALID.join(', ')}`, ''];
  for (const t of TARGETS) {
    const snap = await db.collection('auditoria')
      .where('accion', '==', t.accion).where('objetivo', '==', t.objetivo).get();
    out.push(`── ${t.accion} sobre ${t.objetivo} (aprox. ${t.aprox}) → ${snap.size} registro(s)`);
    for (const d of snap.docs) {
      const when = d.get('creadoEn')?.toDate?.()?.toISOString() ?? '-';
      const autorizado = AUTHORIZED.auditIds.includes(d.id);
      const dist = (a, b) => [...a].filter((c, i) => c !== b[i]).length + Math.abs(a.length - b.length);
      const similar = INVALID.filter((x) => d.id.startsWith(x.slice(0, 8)) || dist(d.id.slice(0, 19), x) <= 2);
      out.push(`  auditoria/${d.id}  creadoEn=${when}  yaAutorizado=${autorizado ? 'sí' : 'no'}  ` +
        `parecidoAIdInvalido=${similar.length ? similar.join(',') : 'no'}`);
    }
  }
  const text = out.join('\n');
  fs.mkdirSync(path.join(__dirname, 'informes'), { recursive: true });
  fs.writeFileSync(path.join(__dirname, 'informes', 'auditoria_faltantes.txt'), `${text}\n`, 'utf8');
  console.log(text);
}

main().catch((e) => { console.error(`Error inesperado: ${e.message}`); process.exit(1); });
