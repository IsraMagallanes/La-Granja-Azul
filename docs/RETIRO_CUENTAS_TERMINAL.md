# Retiro del sistema antiguo de terminales

El proyecto `la-granja-azul-app` es el Firebase temporal de desarrollo y pruebas,
y el propietario autorizó (2026-11-27) retirar y eliminar definitivamente el
sistema antiguo de terminales **y sus datos asociados**. La asistencia ahora la
registra cada trabajador escaneando el QR que muestran Superadmin, Admin o
Cajero (ver `docs/ESTADO_PROYECTO.md`).

## Estado

| Parte | Estado |
|---|---|
| Código de la app (pantallas, rutas, menú, controladores, servicios, permisos, sesión) | **Retirado** (local, sin commit) |
| `firestore.rules` (sin `isTerminal()` ni colecciones de terminales) | **Desplegado el 2026-11-27** |
| Datos en Firebase (documentos y cuentas de Authentication) | **Purgados el 2026-11-27** (38 de 38; ver «Paso 2»). Verificado de nuevo en vivo: Firestore ya no tiene ninguna colección de terminales |
| Herramientas antiguas (`delete_terminal.js`, retiro de cuentas) | Retiradas; se sustituirán por una única herramienta de purga con simulación por defecto |

Un cliente ya **no puede** leer ni escribir `terminales`, `terminalClaves`,
`terminalPruebas` ni `solicitudesEliminacionTerminal` (regla final de denegación
y pruebas en `tools/asistencia.rules.test.js`). Las reglas nuevas se desplegaron el 2026-11-27 (ver «Revisión final de reglas» en `docs/ESTADO_PROYECTO.md`).

## Paso 1: auditoría (solo lectura)

```powershell
cd tools; npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:\ruta\fuera-del-repo\clave.json'
node inventory_terminal_accounts.js          # informe en texto
node inventory_terminal_accounts.js --json   # mismo contenido en JSON
```

No escribe nada (hay pruebas sobre el código y sobre el estado de los
emuladores). Informa de:

- cada cuenta candidata con su veredicto (`TERMINAL EXCLUSIVA`, `EXCLUIDA` con el
  criterio incumplido, o `SIN CUENTA AUTH`), y los documentos que tiene
  (`terminales`, `terminalClaves`, `terminalPruebas`, solicitud de eliminación);
- sus referencias: asistencias (`terminalId`), auditoría y tokens;
- la clasificación de `qrTokens`: del **sistema nuevo** (nunca se tocan), antiguos
  usados y referenciados por una asistencia (**se conservan**: son historia de
  trabajadores reales), antiguos usados sin asistencia y antiguos sin usar
  (**residuos**);
- los registros de auditoría del sistema antiguo de terminales.

## Paso 1b: simulación de la purga (solo lectura)

```powershell
cd tools
$env:GOOGLE_APPLICATION_CREDENTIALS = 'C:utauera-del-repoclave.json'
node purge_terminals_dryrun.js
```

Verifica solo los elementos autorizados por el propietario (3 UIDs, 8 `qrTokens`, 21 ids de `auditoria`, documentos de `terminales` y `terminalPruebas`), excluye con motivo los que no coincidan y escribe `tools/informes/purga_terminales_simulacion.txt`. **No existe modo de eliminación**; `tools/terminal_purge_plan.test.js` comprueba que el código no contiene escrituras. La ejecución real requiere aprobación expresa.

## Paso 1c: respaldo y reverificación previos (solo lectura)

Después de la simulación (38 candidatos aprobados como lista), `node prepare_purge_backup.js` vuelve a consultar Firebase, compara con el informe anterior, excluye lo que haya cambiado, guarda en `tools/backups/purga_terminales_<fecha>/` (fuera de git, confidencial) un respaldo con manifiesto SHA-256 y escribe `tools/informes/purga_terminales_previa.txt`. No guarda hash de contraseña de Authentication. **Sigue sin existir ninguna eliminación implementada.**

## Paso 2: purga real autorizada (2026-11-27)

El propietario autorizó eliminar exactamente los 38 elementos del informe previo. `tools/execute_terminal_purge.js --backup <carpeta> --confirmar ELIMINAR-38` verifica el respaldo (SHA-256), vuelve a consultar Firebase y **aborta sin borrar nada** ante cualquier diferencia; si falla a mitad, se detiene e informa eliminados y pendientes. No toca `terminalClaves`, `solicitudesEliminacionTerminal`, asistencias, perfiles ni otras cuentas. Escribe `tools/informes/purga_terminales_resultado.txt`. **Estado: EJECUTADA el 2026-11-27 (17:52 UTC): 38 de 38 eliminados** (3 cuentas de Authentication, 3 `terminales`, 3 `terminalPruebas`, 8 `qrTokens`, 21 `auditoria`); verificación en vivo correcta. Quedan: 6 asistencias, 5 perfiles, 14 `qrTokens`, 9 `auditoria`, 5 cuentas de Authentication. Respaldo local: `tools/backups/purga_terminales_2026-11-27T17-38-05-625Z` (confidencial, fuera de git). Resultado: `tools/informes/purga_terminales_resultado.txt`. Reglas nuevas desplegadas el 2026-11-27. Los scripts de simulación, búsqueda y respaldo siguen siendo de solo lectura.

## Qué es una «cuenta de terminal exclusiva»

Cumple las **cuatro** condiciones (`tools/lib/terminal_criteria.js`):

1. existe `terminales/{uid}`;
2. **no** existe `usuarios/{uid}` (ni trabajador, ni Caja, ni Admin, ni Superadmin);
3. su correo no está en `correos` y su UID no está en `correos`/`documentos`;
4. su UID nunca aparece como trabajador (`asistencias.uid`) ni como actor
   (`auditoria.actorUid`); solo como `terminalId`.

Si falla cualquiera, la cuenta queda **EXCLUIDA** y no se propone para
eliminación.

## Propuesta de eliminación (a aprobar tras la auditoría)

| Dato | Propuesta |
|---|---|
| Cuentas de Authentication de terminales **exclusivas** | Eliminar |
| `terminales/{uid}`, `terminalClaves/{uid}`, `terminalPruebas/{uid}` de esas cuentas | Eliminar |
| `solicitudesEliminacionTerminal/*` | Eliminar (sin utilidad) |
| `qrTokens` antiguos **sin usar** o **usados sin ninguna asistencia** | Eliminar (residuos) |
| `qrTokens` antiguos usados y referenciados por una asistencia | **Conservar** |
| `qrTokens` del sistema nuevo (`generadorUid`) | **Conservar** |
| `asistencias` (aunque tengan `terminalId`): son de trabajadores reales | **Conservar** |
| `auditoria` del sistema antiguo (actor: el Superadmin real) | **Conservar** salvo orden expresa |
| `usuarios` y cualquier cuenta con perfil | **Nunca** se tocan |

Nada se ejecuta sin la aprobación expresa del propietario sobre la lista exacta
que muestre la auditoría.
