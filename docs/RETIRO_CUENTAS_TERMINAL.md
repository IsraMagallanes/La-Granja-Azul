# Retiro de las cuentas de terminal antiguas

Parte del cambio al sistema de asistencia con QR generado por Caja, Admin y
Superadmin (el trabajador escanea con su propia cuenta). Las cuentas de
Authentication creadas solo para las antiguas terminales dejan de ser necesarias.

**Estado (2026-11-26):** herramientas desarrolladas y probadas **solo con
emuladores**. **No se ha ejecutado nada contra Firebase real**: no se leyó ni se
modificó Authentication ni Firestore de producción, no se deshabilitó ni eliminó
ninguna cuenta y no se desplegaron reglas. El código antiguo de autenticación de
terminal sigue en la app.

**Cuentas clasificadas para retiro (decisión del propietario, sin ejecutar):**
`qcws9YWDVPef3THHTQESmdE3LyC3` (Asistencia), `WlEJWNwIvFRzULaO1hQ6vYxbTjF2`
(La Granja Azul) y `29519GHJw0RHouh6yj4lcdQkIVg1` (prueba). Ninguna seguirá
como terminal: se retirarán con `--retirar-cuenta --marcar-retirada`, que
conserva `terminales/{uid}`. El script vuelve a comprobar los cuatro criterios al
ejecutar. Contexto completo: `docs/PROPUESTA_ASISTENCIA_QR_E_INVENTARIOS.md`.

## Qué es una «cuenta de terminal exclusiva»

Cumple las **cuatro** condiciones (`tools/lib/terminal_criteria.js`, definición
única que usan el inventario y el retiro):

1. existe `terminales/{uid}`;
2. **no** existe `usuarios/{uid}` (ni trabajador, ni Caja, ni Admin, ni Superadmin);
3. su correo no está en `correos` y su UID no está en `correos`/`documentos`;
4. su UID nunca aparece como trabajador (`asistencias.uid`) ni como actor
   (`auditoria.actorUid`); solo como `terminalId`.

Si falla cualquiera, la cuenta queda **EXCLUIDA** y ninguna herramienta la toca.

## Paso 1 — Inventario (solo lectura)

```powershell
cd tools; npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
node inventory_terminal_accounts.js          # informe en texto
node inventory_terminal_accounts.js --json   # mismo contenido en JSON
```

No escribe nada (hay una prueba que lo verifica sobre el código y otra sobre el
estado completo de los emuladores). Por cuenta muestra UID, correo enmascarado,
nombre y estado de la terminal, estado de Authentication, qué documentos de
enlace existen, referencias (asistencias, auditoría, tokens usados) y el
veredicto: `TERMINAL EXCLUSIVA`, `EXCLUIDA` (con el criterio incumplido) o
`SIN CUENTA AUTH (solo documentos)`. Termina con el resumen de `qrTokens`
(total, usados, sin usar, vencidos, anomalías y referencias). Coste de lectura:
unos pocos documentos por cuenta más los `qrTokens` sin usar (dentro de la cuota
gratuita de Spark para un restaurante).

## Paso 2 — Modo `--retirar-cuenta`

```powershell
node delete_terminal.js <uid> --retirar-cuenta                       # simulación (por defecto)
node delete_terminal.js <uid> --retirar-cuenta --execute             # terminal que migra a Caja
node delete_terminal.js <uid> --retirar-cuenta --marcar-retirada --execute   # terminal que se retira del todo
```

| | Migra a Caja | Se retira del todo (`--marcar-retirada`) |
|---|---|---|
| Cuenta de Authentication | se elimina | se elimina |
| `terminalClaves`, `terminalPruebas`, solicitud de eliminación | se eliminan | se eliminan |
| `terminales/{uid}` | **sin modificar** (nombre, estado, historial) | se conserva y queda `activo:false`, `retirada:true`, `retiradaEn` |
| `asistencias`, `auditoria` | se conservan | se conservan |
| `qrTokens` (usados **y** sin usar) | se conservan | se conservan |

- Simulación por defecto; `--execute` exige terminal interactiva y escribir el
  ID del proyecto y el UID.
- Verifica los cuatro criterios también al ejecutar: una cuenta normal queda
  `BLOQUEADA`.
- Deja una entrada de auditoría `retirar_cuenta_terminal` (actor
  `script-local`). Es seguro repetirlo si se interrumpe (no duplica la auditoría).
- La tablet que migra deberá volver a enlazarse (el secreto antiguo se elimina);
  eso pertenece al flujo nuevo con Caja.

## Tokens `qrTokens`

El inventario solo informa. **No se purga ninguno.** Los tokens usados son la
referencia histórica (`asistencias.tokenId`/`salidaTokenId`) y se conservan. La
purga de los sin usar (temporales, esquema antiguo) queda a decisión del
propietario tras revisar las cantidades.

## Pruebas (solo emuladores)

`tools/terminal_inventory.test.js` y `tools/terminal_retirement.test.js`,
incluidas en `npm run test:rules`. Cubren: clasificación (exclusiva, personal,
índices, trabajador/actor, huérfana, sin Auth), datos del informe y
enmascarado, cantidades de tokens, solo lectura, retiro con y sin marca,
conservación de tokens/asistencias/auditoría, bloqueo de cuentas de personal,
fallos parciales y reanudación, y las salvaguardas de la línea de comandos.

## Pendiente (requiere autorización expresa)

1. Ejecutar el inventario contra Firebase real y revisar la lista.
2. Indicar qué terminales migran a Caja y cuáles se retiran.
3. Decidir la purga de tokens sin usar.
4. Ejecutar el retiro (`--execute`), cuenta por cuenta.
5. Retirar el código antiguo de autenticación de terminal (`TerminalAuthenticated`,
   `isTerminal()`, rutas y permisos) y actualizar `firestore.rules`.
6. Al retirar `terminales`, las reglas y la app deberán admitir los campos
   `retirada`/`retiradaEn` (hoy `hasOnly` los rechazaría en una escritura
   desde la app; el script usa Admin SDK y no pasa por reglas).
