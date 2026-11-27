# Propuesta técnica: asistencia QR, retiro de Almacén e inventarios separados

**Estado (2026-11-26): propuesta aprobada en sus decisiones; NADA implementado.**
No se ha cambiado `firestore.rules`, la app, ni Firebase real. No se ha
reasignado ni eliminado ningún perfil, no se ha deshabilitado ni eliminado
ninguna cuenta, no se ha purgado ningún token y no se han desplegado reglas.
Lo único creado hasta ahora son herramientas de solo lectura y de retiro
(probadas solo con emuladores): ver `docs/RETIRO_CUENTAS_TERMINAL.md` y
`tools/inventory_almacen_users.js`.

## 1. Decisiones aprobadas

| | Decisión |
|---|---|
| A | Se elimina el enlace con dispositivos físicos. Caja, Admin y Superadmin generan QR desde sus sesiones habituales; la auditoría identifica al generador. Los documentos históricos de terminales se conservan. |
| B | Caja genera QR y escanea los generados por Admin o Superadmin para su propia entrada y salida. Caja nunca escanea un QR que ella generó. Admin y Superadmin mantienen su exención. Mesero y Cocina escanean desde sus dispositivos. |
| C | Cocina administra existencias y movimientos de insumos (entradas, salidas, mermas, ajustes, consumo por recetas). Admin y Superadmin administran proveedores, costos y recepción de compras, con las restricciones de recepción y protecciones contra duplicados actuales. |
| D | Utensilios: catálogo (crear, editar, desactivar) solo Admin y Superadmin; Mesero registra entregas, devoluciones, pérdidas, daños y deterioros; Mesero, Admin y Superadmin consultan existencias e historial; cada entrega se asocia a un mesero concreto; costo unitario opcional para valorar pérdidas y daños; historial y responsables conservados; sin stock negativo; disponibles ≠ en uso. |
| E | Inventario de perfiles Almacén de solo lectura (`tools/inventory_almacen_users.js`), sin tocar perfiles. |
| — | Cuentas de terminal antiguas `qcws9YWDVPef3THHTQESmdE3LyC3` (Asistencia), `WlEJWNwIvFRzULaO1hQ6vYxbTjF2` (La Granja Azul), `29519GHJw0RHouh6yj4lcdQkIVg1` (prueba): clasificadas para retiro (`--retirar-cuenta --marcar-retirada`), sujeto a autorización final. Ninguna seguirá como terminal. |
| — | Se conservan asistencias, auditorías y tokens usados; los seis tokens vencidos sin usar quedan pendientes de decisión (no se purgan). `terminales/{uid}` no se elimina hasta verificar nombres en reportes. |

**Supuestos a confirmar** (no estaban explícitos):
1. Compras y proveedores son solo de Admin/Superadmin (crear, recibir, cancelar). Cocina no los usa.
2. Cocina crea insumos y edita nombre, mínimo y activo; el costo solo lo cambia Admin.
3. Un Cajero solo escanea QR de Admin o Superadmin (no de otro Cajero).
4. Alta de stock inicial y ajustes de utensilios: solo Admin/Superadmin.
5. El destinatario de una entrega puede ser cualquier mesero activo, no solo quien registra.

## 2. Asistencia QR

### Roles

| Rol | Genera QR | Escanea | Registra asistencia |
|---|---|---|---|
| Superadmin, Admin | sí | no | exentos (sin cambios) |
| Cajero | sí | solo QR de Admin/Superadmin | sí (al escanear) |
| Mesero, Cocina | no | sí | sí (al escanear) |

Iniciar o cerrar sesión **nunca** registra asistencia. La entrada o salida la
decide la jornada: sin jornada abierta solo cabe una entrada; con jornada abierta,
solo una salida (`estadoAsistencia`, como hoy).

### Datos

- `sesionesQr/{id}`: `generadoPor`, `rol`, `activa`, `tokenActual`, `creadaEn`,
  `vigenteHasta` (se renueva con latido), `cerradaEn`. Sin `terminalId`.
- `qrTokens/{id}` (esquema nuevo): `sesionId`, `generadoPor`, `generadoPorRol`,
  `creadoEn`, `usadoEn`, `usadoPor`. Vida de 45 s, un solo uso, a demanda.
- `asistencias`: `uid` (quien escanea), `generadoPor`, `sesionId`, `tokenId`,
  `origen: 'qr'`, horas del servidor.

### Reglas (en un solo lote atómico: token usado + asistencia + estado)

1. Escanea un Mesero, Cocina o Cajero activo con correo verificado y
   `uid == request.auth.uid`.
2. Si escanea un Cajero, `generadoPorRol in ['admin','superadmin']`.
3. `usadoPor != generadoPor` (nadie se marca con su propio QR).
4. Token sin usar, de menos de 45 s y es el `tokenActual` de su sesión activa
   y vigente; el generador sigue activo y con rol autorizado.
5. Entrada/salida coherente con `estadoAsistencia`; `entrada`/`salida ==
   request.time`.
6. Genera solo Cajero, Admin o Superadmin; Mesero y Cocina denegados por regla.

### Se retira (después de aprobar la implementación)

`isTerminal()`, `terminalClaves`, `terminalPruebas`, `TerminalAuthenticated`,
`TerminalScanService`, `TerminalBindingService`, `QrIssueService`,
`terminal_screen`, ruta `/asistencia/terminal` y la creación de cuentas de
terminal. `terminales` queda como historial de solo lectura (Superadmin).

### Nombres de terminales en reportes

Ningún reporte ni pantalla de asistencia lee hoy `terminalId` (el modelo
`AttendanceRecord` no lo incluye); el nombre solo aparece en la pantalla de
Terminales y en `auditoria.campos`. Conservar `terminales/{uid}` basta para que
cualquier reporte futuro resuelva el nombre por `terminalId`, sin modificar
asistencias históricas.

## 3. Retiro del rol Almacén

- **Código:** `UserRole.almacen`, `StaffPolicy.operationalRoles`,
  `PermissionService` y la matriz (`tools/fixtures/permission_matrix.json`).
- **Reglas:** `operationalRoles()`, `assignableRoles()`, `canStock()`.
- **Pruebas:** ≥ 10 suites de reglas y 7 de Flutter con semillas o casos de
  Almacén. **Documentación:** README y 7 archivos de `docs/`.
- Rutas, reportes e indicadores no lo mencionan; los formularios toman los
  roles del enum, así que se corrigen solos.

**Riesgo si se retira con perfiles Almacén vivos:** `UserRole.tryParse` devuelve
`null`; `AppUser.fromMap` y `StaffMember.fromMap` descartan el perfil (el usuario
ve «sin perfil» y desaparece de la lista) y las reglas impedirían a un Admin
editarlo, suspenderlo o darlo de baja (`rol in assignableRoles()`). Por eso cada
perfil se resuelve **antes** del despliegue, con la app actual (queda auditado).

**Inventario de perfiles:** `node inventory_almacen_users.js [--json]`. Muestra
UID, nombres de pila, estado, fechas, jornada, estado de Authentication
(correo enmascarado) y cuántos registros referencian a cada perfil
(movimientos, compras creadas/pendientes/recibidas/canceladas, recetas,
asistencias, correcciones, auditoría, movimientos de personal, tokens). No
expone documento, celular, apellidos ni correo completo. Lista aparte los
perfiles con rol no reconocido (p. ej. variantes de escritura de «almacén»).

**Conservación del histórico:** movimientos, compras y auditoría guardan `uid` y
un nombre copiado (`creadoPorNombre`, `recibidoPorNombre`, `actorNombre`), no el
rol. Cambiar el rol o dar de baja un perfil no los altera, y los perfiles no se
borran. No se reasigna a nadie automáticamente.

## 4. Inventario dividido

> **Vigente: §8.** Las decisiones posteriores (costos protegidos, máximo de 5
> líneas por compra, Mesero con las cinco operaciones, costos de utensilios en
> documentos protegidos) sustituyen lo que este apartado dice sobre costos,
> líneas de compra y campos de utensilios.

Se conservan los nombres de colección y los datos actuales de insumos
(`insumos`, `movimientosInventario`, `recetas`, `proveedores`, `compras`,
`descuentosInventario`, `excepcionesInventario`): migración de datos cero.

### Insumos (Cocina)

| Acción | Cocina | Admin / Superadmin |
|---|---|---|
| Ver existencias, movimientos, alertas, recetas | sí | sí |
| Entrada, salida, merma, ajuste, consumo por receta | sí | sí |
| Crear insumo; editar nombre, mínimo, activo | sí | sí |
| Costo unitario | no | sí |
| Proveedores; crear, recibir y cancelar compras | no | sí |

Jornada abierta para Cocina (los exentos no la necesitan). Se mantienen:
movimiento y stock en el mismo lote, sin stock negativo, quien crea una compra
no la recibe (salvo Admin) y la recepción exacta línea por línea. Cambios:
`canStock()` pasa de `almacen,admin,superadmin` a `cocina,admin,superadmin`;
proveedores y compras pasan a `isAdmin()`; `AppModule.inventory` se renombra a
`AppModule.supplies`; ruta `/app/insumos`.

### Utensilios (Mesero) — modelo independiente

Sin recetas, sin descuentos por pedido y sin relación con insumos.

- `utensilios/{id}`: `nombre`, `disponible`, `enUso`, `stockMinimo`,
  `costoUnitario` (opcional, centavos), `activo`, `ultimoMovimiento`,
  `creadoEn`, `actualizadoEn`. Total = `disponible + enUso`. Catálogo (crear,
  editar, desactivar y costo): solo Admin/Superadmin.
- `asignaciones/{utensilioId}_{meseroId}`: `cantidad` en poder de ese mesero. Cada
  movimiento actualiza utensilio y asignación en el mismo lote (`getAfter`), de
  modo que lo «en uso» siempre se reparte entre meseros concretos y nunca se
  confunde con lo disponible.
- `movimientosUtensilios/{id}` (solo de agregar): `utensilioId`, `tipo`,
  `cantidad`, `meseroId`/`meseroNombre` (obligatorio en entrega, devolución,
  pérdida, daño y deterioro), `costoUnitario` y `valor` (copia del costo vigente,
  para valorar), `motivo`, `creadoPor`, `creadoPorNombre`, `creadoEn`.
- Tipos y efecto: `entrega` (disponible → en uso del mesero), `devolucion` (en uso
  del mesero → disponible), `perdida`/`dano`/`deterioro` (bajan lo que el mesero
  tiene en uso; reducen el total; motivo obligatorio), `alta` y `ajuste` (solo
  Admin/Superadmin).
- Reglas: `canUtensils()` = Mesero (con jornada), Admin, Superadmin; lectura de
  existencias e historial para los tres; sin negativos en `disponible`, `enUso`
  ni asignación; el destinatario debe ser un mesero activo; sin borrado.
- Alertas: `disponible < stockMinimo`. Ruta `/app/utensilios`, `AppModule.utensils`.
  Cocina y Caja no reciben acceso.

## 5. Cambios por capa

- **Reglas:** quitar Almacén y el bloque de terminal; asistencia QR nueva
  (`sesionesQr`, `qrTokens`, `asistencias`, `estadoAsistencia`); `canStock` →
  Cocina; proveedores y compras Admin; reglas de utensilios.
- **Servicios/modelos:** `UserRole`, `StaffPolicy`, `PermissionService`,
  `AppModule`; `QrGenerateService`, `QrScanService`; `UtensilService`,
  repositorio y modelos; `InventoryService` ajustado a Cocina/Admin.
- **Pantallas:** Generar QR (Cajero, Admin, Superadmin); escáner del trabajador
  (Mesero, Cocina, Cajero); Insumos (renombrada); Utensilios (nueva); Terminales
  pasa a listado histórico; se ajustan rutas, `AuthRedirect` y menús.
- **Pruebas:** reescribir `asistencia.rules.test.js`; actualizar
  `inventario.rules.test.js`, `permissions.rules.test.js`, fixture de la matriz y
  las semillas con Almacén; nuevas: `utensilios.rules.test.js`, sesiones QR,
  `utensil_test`, `qr_scan_test`.

## 6. Plan de migración

1. **(Hecho)** Herramientas de solo lectura y de retiro, probadas en emuladores.
2. El propietario ejecuta `inventory_almacen_users.js` contra Firebase real y
   decide, por UID, qué hacer con cada perfil.
3. Aplicar esas decisiones con la app actual (cambio de rol, suspensión o baja,
   con auditoría). Repetir el inventario hasta que no queden perfiles Almacén ni
   roles desconocidos.
4. Implementar y probar en emuladores (QR, retiro de Almacén, inventarios), tras
   autorización.
5. Despliegue único de reglas y app (autorización expresa).
6. Prueba física con checklist actualizado.
7. Retirar las tres cuentas de terminal con `--marcar-retirada` (autorización
   expresa tras revisar la lista); `terminales/{uid}` se conserva.
8. Retirar el código antiguo de terminales.
9. Decidir la purga de los seis tokens vencidos y una política TTL.

## 7. Riesgos

- Un QR fotografiado y reenviado permite marcar sin estar en el local; lo limitan
  los 45 s, el uso único y la auditoría del generador. No hay verificación de
  ubicación en reglas.
- Sin Cloud Functions el cierre de sesión es de mejor esfuerzo; `vigenteHasta`
  acota la exposición.
- Cuota de escrituras de Spark (20 000/día): por eso el QR se genera a demanda.
- Un perfil Almacén sin resolver quedaría inaccesible y no administrable tras el
  despliegue (ver §3).

## 8. Etapa de inventarios: plan técnico vigente (2026-11-26)

**Estado:** sin implementar. Hecho hasta ahora: solo `tools/migrate_supply_costs.js`
(desarrollado y probado con emuladores; **no ejecutado contra Firebase real**).
Confirmado por el propietario: 0 perfiles Almacén y 0 roles desconocidos.

### 8.1 Decisiones

1. Mesero registra entregas, devoluciones, pérdidas, daños y deterioros; el
   catálogo, el stock inicial (`alta`) y los `ajuste` son de Admin y Superadmin.
2. Quien registra una entrega elige a cualquier Mesero activo; el movimiento guarda
   `meseroId` y `meseroNombre` de quien recibe.
3. Utensilios: solo Mesero, Admin y Superadmin. Cocina y Cajero, sin acceso.
4. Proveedores y compras: ruta `/app/compras`, solo Admin y Superadmin.
5. `costoUnitario = 0` significa «costo no registrado».
6. Los cambios del catálogo de utensilios generan registros en `auditoria`.
7. Cocina no lee costos de insumos (datos separados, no solo ocultos en pantalla).
8. **Recepción de compras: Opción B.** La regla valida el costo de cada línea y una
   compra admite **como máximo 5 líneas**.
9. **Costos de utensilios protegidos:** el Mesero no lee costos unitarios ni
   valoraciones; Admin y Superadmin sí.
10. Migración de costos de insumos: script autorizado solo para desarrollo y pruebas
    en emuladores.

### 8.2 Matriz de permisos

| Módulo | Superadmin / Admin | Cocina | Mesero | Cajero |
|---|---|---|---|---|
| `supplies` ver, crear, editar | sí | sí | no | no |
| `supplies` especial (costos) | sí | **no** | no | no |
| `purchasing` | ver, crear, editar | no | no | no |
| `utensils` | ver, crear, editar | **no** | ver, crear (registrar movimientos) | **no** |
| `utensils` especial (costos y valoración) | sí | no | **no** | no |

### 8.3 Costos de insumos

- **`costosInsumos/{insumoId}`:** `costoUnitario`, `actualizadoEn`,
  `actualizadoPor`. Lectura y escritura solo Admin y Superadmin; sin borrado. Un
  insumo sin documento de costo = costo no registrado.
- `insumos` y los movimientos `compra` dejan de tener `costoUnitario`. El costo de
  cada compra vive en `compras.lineas` (solo Admin).
- Recetas: no guardan costos. Cocina ve ingredientes y cantidades; el costo y el
  margen los calcula Admin con `costosInsumos`. Reportes (solo Admin) leen
  `costosInsumos` para costo de platos, mermas y valoración. Ninguna pantalla de
  Cocina observa el proveedor de costos.
- **Integridad de la recepción (Opción B):** al recibir, el movimiento `compra` de
  cada línea exige `getAfter(costosInsumos/{insumo}).costoUnitario ==
  compra.lineas[linea].costoUnitario`. La regla de `costosInsumos` no consulta el
  insumo (ahorra accesos): pueden existir documentos de costo huérfanos, que son
  inofensivos (solo Admin).
- **Datos existentes:** la separación solo es completa tras
  `migrate_supply_costs.js` (ver 8.7). Mientras queden campos antiguos, Cocina los
  leería.

### 8.4 Utensilios

- **`utensilios/{id}`:** `nombre`, `disponible`, `enUso`, `stockMinimo`, `activo`,
  `versionCosto` (entero, 0 = sin costo; no es un importe), `ultimoMovimiento`,
  `ultimaAuditoriaId`, `creadoEn`, `actualizadoEn`. Sin ningún importe.
- **`costosUtensilios/{utensilioId}_{version}`:** inmutable y solo Admin/Superadmin:
  `utensilioId`, `version`, `costoUnitario` (≥ 0; 0 = no registrado),
  `vigenteDesde == request.time`, `creadoPor`. Se crea en el mismo lote que sube
  `versionCosto` del utensilio (`version == antes + 1`, comprobado con `getAfter`).
- **`asignacionesUtensilios/{utensilioId}_{meseroId}`:** `cantidad`, `meseroNombre`,
  `ultimoMovimiento`. Solo cambia junto a un movimiento.
- **`movimientosUtensilios/{id}`** (solo agregar): `tipo`, `cantidad`,
  `deltaDisponible`, `deltaEnUso`, `disponibleResultante`, `enUsoResultante`,
  `meseroId`, `meseroNombre`, `versionCosto` (copiada del utensilio y validada),
  `motivo`, `creadoPor`, `creadoPorNombre`, `creadoEn`. **Sin importes.**
- **Valoración de pérdidas y daños:** el Mesero no puede copiar un costo que no
  lee, y las reglas no pueden rellenar campos. Por eso el movimiento guarda solo la
  `versionCosto` vigente; Admin calcula `cantidad × costosUtensilios/{id}_{version}`
  en su pantalla, con el costo exacto de ese momento y sin que el Mesero lo vea.
- **Reglas:** `canUtensils()` = Mesero (jornada abierta), Admin, Superadmin. Mesero
  registra `entrega`, `devolucion`, `perdida`, `dano`, `deterioro`; `alta` y
  `ajuste` solo Admin. Destinatario: Mesero activo. Sin negativos en `disponible`,
  `enUso` ni asignación; una devolución o baja no supera lo asignado; utensilio
  desactivado no recibe movimientos; movimientos inmutables y sin borrado; un
  movimiento por cambio de stock (`ultimoMovimiento`).
- **Auditoría del catálogo:** crear, editar y activar/desactivar escriben una
  entrada en `auditoria` en el mismo lote (`auditOk`), con las acciones
  `crear_utensilio` y `editar_utensilio` y los campos cambiados (sin importes).
  Los cambios de costo quedan además en las versiones inmutables.

### 8.5 Límites de accesos de Firestore (revisión)

Producción admite 10 accesos (`get/exists/getAfter`) por operación y 20 por
lote o transacción; el emulador **no** los aplica, así que estas cifras son
cálculo y **deben validarse en Firebase real**. Criterio conservador: `get` y
`getAfter` del mismo documento cuentan por separado.

| Caso | Por operación | Por lote | Margen |
|---|---|---|---|
| Recibir compra, n líneas (usuario, compra ×2, movimiento ×n, insumo ×n, costo ×n) | ≤ 6 | 3 + 3n → **18 con n = 5** (21 con n = 6) | 2 |
| Mismo caso antes (sin costo, 8 líneas) | — | 19 | 1 |
| Cocina marca «Listo» con 8 insumos (Fase 8B) | sin cambio | sin cambio (los costos no intervienen) | el existente |
| Cocina: movimiento manual de stock | ~4 | ~4 | amplio |
| Mesero: entrega (usuario, jornada, destinatario, utensilio ×2, asignación ×2, movimiento) | ~6 | ~9 | amplio |
| Admin: editar catálogo de utensilios con costo (usuario, utensilio, auditoría) | ~3 | ~4 | amplio |

- Por eso el máximo de 5 líneas: con 6 el lote pasaría de 20. Cualquier regla que
  añada un acceso a la recepción (por ejemplo, comprobar que el insumo exista al
  escribir su costo) la dejaría sin margen: no se añade.
- Escrituras: como mucho 16 documentos por lote (1 compra, 5 movimientos, 5 insumos,
  5 costos), lejos del tope de 500.
- Expresiones por evaluación (límite 1000): `validPurchase` se acorta al pasar de 8
  a 5 líneas.
- **Compras pendientes anteriores con más de 5 líneas** no podrían recibirse (solo
  cancelarse o rehacerse). La simulación de la migración las lista.

### 8.6 Revisión de seguridad de las reglas

- Cocina: denegado en `costosInsumos`, `compras`, `proveedores`,
  `excepcionesInventario` y reportes; crea insumos sin costo y no registra el tipo
  `compra`.
- `insumos` rechaza el campo `costoUnitario`: tras la migración, ni Cocina ni nadie
  puede reintroducirlo.
- Recibir una compra solo la hace Admin: un movimiento `compra` exige además que la
  compra pase de pendiente a recibida en el mismo lote (sin duplicados), con quien
  la creó impedido de recibirla (salvo Admin), y ahora con el costo validado.
- Utensilios: Mesero sin lectura de `costosUtensilios`; sin campos de importe en
  `utensilios` ni en movimientos (las reglas de creación usan `hasOnly`).
- Un movimiento no se puede duplicar, editar ni borrar; el stock solo cambia con un
  movimiento nuevo (`creadoEn == request.time`) al que apunta `ultimoMovimiento`.
- Las reglas leen `costosUtensilios` con `get()` aunque el usuario no pueda leerlas.

### 8.7 Migración de costos de insumos (`tools/migrate_supply_costs.js`)

Desarrollada y probada con emuladores (19 pruebas). **No se ha ejecutado contra
Firebase real** y necesita autorización expresa aparte.

- **Simulación por defecto**; `--execute` exige terminal interactiva y escribir el
  ID del proyecto y «MIGRAR COSTOS».
- Copia `insumos.costoUnitario` a `costosInsumos` solo con `create` (nunca
  sobrescribe) y relee las copias antes de quitar nada.
- **Conflictos que bloquean todo sin cambiar nada:** costo no válido; costo ya
  existente y distinto; movimiento con costo que no es de compra; movimiento de
  compra cuyo insumo o costo no coincide con su línea en `compras`, o cuya compra o
  línea no existe.
- Solo quita el campo `costoUnitario` (con precondición de la última modificación
  leída: si alguien cambia el documento entretanto, esa operación falla y se puede
  repetir). No toca ningún otro campo ni documento; añade una entrada de auditoría
  `migrar_costos_insumos`.
- Idempotente y reanudable; procesa por lotes de 200.
- Lista las compras pendientes con más de 5 líneas.
- Es el único cambio previsto sobre documentos históricos (quitar un campo
  duplicado): el valor queda en `costosInsumos` y, en las compras, en
  `compras.lineas`.
- **Orden recomendado:** simulación → copia de costos → despliegue de reglas y app
  nuevas → limpieza de campos. Las fases de inventario aún no están desplegadas, así
  que la simulación podría informar cero documentos.

### 8.8 Archivos del plan

- **Dart, modificar:** `user_role`, `staff_policy`, `permission`,
  `permission_service`, `app_routes`, `app_router`, `firestore_paths`, `main`,
  `audit_entry`; inventario (modelos con el costo separado, `Recipe.cost` con
  mapa de costos, repositorio —recepción con 5 líneas y costos—, servicio,
  providers, pantallas y diálogos) y reportes (modelos, providers, repositorio,
  pantalla).
- **Dart, nuevos:** `features/purchasing/` y `features/utensils/` (con su proveedor
  de costos solo para Admin).
- **Reglas y pruebas:** `firestore.rules`; actualizar las suites de inventario,
  descuento, permisos, `rules.test.js` y las semillas con Almacén; nuevas:
  `utensilios.rules.test.js` (incluye costos protegidos y auditoría), pruebas de
  `costosInsumos` y de recepción con 5 líneas, `utensils_test.dart`; matriz y
  fixture regenerados.
- **Ya creados:** `tools/migrate_supply_costs.js`,
  `tools/lib/supply_costs_migration.js`, `tools/migrate_supply_costs.test.js`.
- **Documentación:** README, `ESTADO_PROYECTO`, checklists de inventario y uno nuevo.

### 8.9 Riesgos pendientes

1. Los límites de accesos no se pueden comprobar en el emulador: validar en Firebase
   real (margen de 2 accesos en la recepción).
2. Los costos antiguos siguen legibles para Cocina hasta ejecutar la migración y
   desplegar las reglas; la limpieza modifica documentos históricos.
3. El costo de un insumo no tiene historial (una sola versión): mermas y
   valoraciones usan el costo vigente. El de utensilios sí se versiona.
4. Documentos huérfanos en `costosInsumos` posibles e inofensivos.
5. Una edición manual de un costo de insumo no deja auditoría propia (solo
   `actualizadoPor/En`); añadirla es posible, pero cuesta un acceso más en cada
   edición suelta (no en la recepción).
6. Compras pendientes de más de 5 líneas quedan sin recepción posible.
7. El descuento por pedido sigue calculándose en el cliente (límite documentado de
   las reglas), y el límite de 20 de la Fase 8B sigue pendiente de validar.

### 8.10 Implementación (2026-11-27)

Implementado en local; **sin desplegar, sin commit, sin migración real y sin
tocar Firebase real**. Cambios: rol Almacén retirado (roles, permisos, rutas,
reglas, pruebas, documentación; el historial no se borra), módulos Insumos,
Compras y Utensilios, `costosInsumos`, utensilios con asignaciones por Mesero,
movimientos inmutables y catálogo auditado, y costos de utensilios versionados.
La herramienta `tools/inventory_almacen_users.js` queda como diagnóstico legado
de perfiles Almacén previos.

Pruebas ejecutadas el 2026-11-27: 584 de reglas (emulador, 18 archivos) y `flutter test`
(366 OK); `flutter analyze` sin errores ni advertencias (solo infos previas).
Cálculo y sonda de límites: `docs/LIMITES_FIRESTORE.md`
(sonda **no ejecutada**). Checklist: `docs/CHECKLIST_FISICO_INVENTARIOS.md`.

Pendientes: migración de costos, despliegue de reglas, validación real de límites.

### 8.11 Etapa 1 de puesta a punto (2026-11-27)

El Firebase `la-granja-azul-app` es de desarrollo y pruebas (la versión definitiva
usará otro proyecto, más adelante). Cambios de esta etapa, sin desplegar:

- **Fase 8B:** cadena de movimientos y transición probada con `listoEn == request.time`
  (4 + 2n accesos; ver `docs/LIMITES_FIRESTORE.md`).
- **Directorio de meseros** (`directorioMeseros/{uid}`: solo `nombre`, `activo`,
  `actualizadoEn`): lo leen Mesero y administración; solo Admin/Superadmin lo escriben, en el
  mismo lote que el cambio del perfil (alta, edición, cambio de estado), y la regla exige que
  coincida con el perfil (un `getAfter`). La app del Admin lo reconcilia al abrir Utensilios.
  No concede nada: el movimiento valida al destinatario contra `usuarios`. Sustituye la
  limitación anterior del selector.
- **Migración de costos:** el script ahora escribe una copia de seguridad JSON en
  `tools/backups/` (ignorada por git) antes de ejecutar.
