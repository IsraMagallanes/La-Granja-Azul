/**
 * Lógica pura (sin red ni Firebase) del cambio de correo del Superadmin.
 * Se separa del script para poder probarla y para que cada pieza tenga una
 * sola responsabilidad: validar, decidir el plan y describirlo.
 */
const EMAIL = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;

function normalizeEmail(raw) {
  return String(raw || '').trim().toLowerCase();
}

/** Devuelve la lista de errores del correo nuevo (vacía si es válido). */
function validateNewEmail(newEmail, currentEmail) {
  const errors = [];
  if (!EMAIL.test(newEmail)) errors.push('El correo no tiene un formato válido.');
  if (newEmail === currentEmail) errors.push('El correo nuevo es igual al actual.');
  return errors;
}

/**
 * Decide qué falta hacer según dónde está el correo hoy. Hace el cambio
 * idempotente: si una ejecución anterior se interrumpió, volver a ejecutarla
 * con el mismo correo completa solo lo pendiente.
 *
 * @param {{authEmail: string, profileEmail: string, newEmail: string}} s
 * @returns {{steps: string[], error?: string}} steps ⊆ ['auth', 'firestore']
 */
function planEmailChange({ authEmail, profileEmail, newEmail }) {
  const authDone = authEmail === newEmail;
  const profileDone = profileEmail === newEmail;
  if (authDone && profileDone) return { steps: [] };
  if (!authDone && !profileDone && authEmail !== profileEmail) {
    return {
      steps: [],
      error: `Authentication (${authEmail}) y Firestore (${profileEmail}) ya difieren entre sí y ninguno es el correo nuevo. Revisa antes de continuar.`,
    };
  }
  const steps = [];
  if (!authDone) steps.push('auth');
  if (!profileDone) steps.push('firestore');
  return { steps };
}

module.exports = { normalizeEmail, validateNewEmail, planEmailChange };
