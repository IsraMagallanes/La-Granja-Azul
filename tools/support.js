// Utilidades compartidas por las pruebas de reglas.
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');

async function createEnv() {
  return initializeTestEnvironment({
    projectId: 'la-granja-azul-app',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
}

/** Ficha de personal completa y válida. */
function staff(overrides = {}) {
  const nombres = overrides.nombres ?? 'Ana';
  const apellidos = overrides.apellidos ?? 'Pérez';
  return {
    email: `${nombres.toLowerCase()}@granja.pe`,
    nombre: `${nombres} ${apellidos}`,
    nombres,
    apellidos,
    tipoDocumento: 'dni',
    numeroDocumento: '12345678',
    celular: '987654321',
    rol: 'mesero',
    estado: 'activo',
    activo: true,
    fechaIngreso: '2026-01-15',
    ultimaAuditoriaId: 'seed',
    ...overrides,
  };
}

module.exports = { createEnv, staff };
