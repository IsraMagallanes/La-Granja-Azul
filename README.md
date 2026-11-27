# La Granja Azul — Plan maestro de desarrollo

> Fuente principal de planificación y seguimiento. Cada fase se ejecuta al escribir **«Siguiente fase»**: se lee este archivo, se implementa solo la primera fase pendiente, se prueba lo modificado, se actualiza este README y se espera revisión. La guía de Git y las versiones del entorno están más abajo (sin cambios). Historial de las fases ya construidas: `docs/ESTADO_PROYECTO.md`, `docs/FASE_4.md`, `docs/FASE_5.md`.

**Última actualización:** 2026-11-19 · **Rama:** `Isra` · **Fases 0 a 8 y 8B completadas en código y pruebas automatizadas (Fase 1 pendiente de revisión visual; pruebas físicas de las fases 2 a 8 pendientes y bloqueadas por falta de dispositivo, cuentas y reglas desplegadas: `docs/CHECKLIST_FISICO_FASE_2.md` a `_8.md`) → Fase 8 en revisión del propietario; después viene la Fase 8B (descuento automático de inventario), sin iniciar**

## Reglas permanentes

- **Git/despliegue:** sin commit ni push, sin desplegar servicios ni reglas, sin Blaze ni Cloud Functions (Firebase Spark), sin exponer credenciales, sin borrar ni revertir cambios existentes.
- **Pruebas:** ejecutar solo las relacionadas con lo modificado; no repetir las que ya pasaron sin cambios relevantes; suite completa solo en cambios transversales o en la Fase 10; ampliar pruebas existentes antes de crear nuevas. Al cerrar cada fase informar qué se ejecutó y por qué, qué no se ejecutó y qué validación queda pendiente. Distinguir **prueba automatizada** de **prueba física real**.
- **«Terminado»:** un módulo no lo está por tener interfaz; requiere lógica, reglas Firestore, permisos, pruebas automatizadas y la prueba física que aplique.
- **Seguridad doble:** todo permiso se aplica en Flutter (`PermissionService`) y en `firestore.rules`, y ambos deben mantenerse alineados.
- **Datos:** conservar el histórico (asistencias, auditoría, pedidos); preferir baja lógica a borrado.
- **Carta pública:** `/carta` sin login, carrito, pagos ni pedidos públicos.
- **Identidad visual (todos los módulos; PC, tablet y celular):** **modelo obligatorio: `docs/referencias/diseno.jpeg`** (encabezados azul marino con logotipo blanco, panel lateral, tarjetas blancas, azul intenso en acciones, etiquetas de estado de colores suaves); azul y blanco; interfaz clara, moderna, limpia y gastronómica; fotografías reales de platos; sin interfaz predominantemente oscura; sin gallinas ni pollos como marca.

## Diagnóstico (Fase 0, 2026-11-12)

**Base técnica:** Flutter + Riverpod + go_router; Firebase Auth + Firestore (proyecto `la-granja-azul-app`, Spark). Arquitectura modular `lib/features/<módulo>/{models,repositories,services,controllers,screens,widgets}` con repositorios inyectados (los widgets no tocan Firebase). Unas 9.900 líneas Dart; 13 archivos de prueba Flutter y 6 de reglas/herramientas Node.

**Git:** (Fase 0) rama `Isra` con 8 archivos modificados y 4 sin seguimiento. A 2026-11-18 el trabajo de las fases 1 y 2 y la eliminación de terminales siguen **sin commit** (decisión del propietario: no hacer commit ni push hasta revisar la Fase 1). Últimos commits: fase 5 (mesas/pedidos), fase 4 (carta), fase 3 (personal/asistencia QR). La numeración de `docs/FASE_*.md` es la histórica anterior y **no** coincide con las fases de este plan.

**Pruebas:** no se ejecutaron en la Fase 0. Las cifras de `docs/ESTADO_PROYECTO.md` (142 pruebas Flutter, 77 de reglas) son de la fase 3 histórica y no están reverificadas.

**Hallazgos transversales**
- **Diseño (Fase 1 rehecha según la referencia):** ver registro de fases. Logotipo = `BrandWordmark` (tipográfico, punto amarillo); sin fotos reales en el repositorio todavía.
- **Permisos:** 18 permisos por módulo/pantalla en `PermissionService` (matriz rol → permisos) y `RoleNavigation`. **No hay** granularidad por acción (lectura/creación/edición/eliminación/especial); `RolesScreen` es placeholder.
- **Asistencia y acceso operativo:** *(resuelto en la Fase 2)* la asistencia ahora condiciona el acceso operativo en Flutter y en reglas; ver Decisión técnica 2.
- **Placeholders (`ModulePlaceholder`, ya con marca):** ya no queda ninguna pantalla con `ModulePlaceholder` (verificado en la Fase 8; el widget sigue existiendo sin uso). El dashboard muestra indicadores de pedidos y mesas, sin ingresos todavía.
- **Colecciones Firestore existentes:** `usuarios, documentos, correos, movimientosPersonal, restricciones, auditoria, horarios, terminales, terminalClaves, terminalPruebas, qrTokens, estadoAsistencia, asistencias, correcciones, categorias, carta, mesas, pedidos(+detalles)`. La regla final `{document=**}` deniega el resto.

## Estado de los 15 módulos

Leyenda: ✅ implementado · 🟡 parcial · 🧩 solo pantalla provisional · ⬜ sin código. «Auto» = pruebas automatizadas; «Físico» = prueba real en dispositivo/Firebase real (ninguna documentada para fases 3–5).

| # | Módulo | Estado | Existente (reutilizar, no duplicar) | Pendiente | Fase |
|---|--------|--------|-------------------------------------|-----------|------|
| 1 | Autenticación y permisos | 🟡 | `features/auth` (login, recuperar, verificar correo, `SessionResolver`, `AuthRedirect`), `features/roles` (6 roles, `Permission`, `PermissionService`, `RoleNavigation`), `features/users`. Auto: `permission_service_test`, `auth_redirect_test`, `login_flow_test`, `rules.test.js` | Hecho en la Fase 2: matriz por módulo y acción, pantalla Roles (solo lectura), prueba de alineación Flutter↔reglas, asistencia como condición de acceso. Pendiente: despliegue de reglas y prueba física (checklist) | 2 ✅ |
| 2 | Gestión de personal | 🟡 | `features/staff` (alta con cuenta, estados, movimientos, restricciones), `users_screen`. Auto: `staff_test`, `personal.rules.test.js` | Los permisos por acción ya cubren personal (ver módulo 1); el alta y las bajas siguen cubiertas por `personal.rules.test.js`. Pendiente: prueba física | 2 ✅ |
| 3 | Control de asistencia | 🟡 | `features/attendance` (terminal que genera QR, escaneo móvil con `mobile_scanner`, horarios, correcciones, reporte, `terminals_screen`). Auto: `attendance_test`, `phase3_widgets_test`, `asistencia.rules.test.js`. **En curso sin commit:** eliminación definitiva de terminales (`tools/delete_terminal.js`, `tools/lib/terminal_deletion.js`, `terminals_screen`, `terminals_screen_test`) | Hecho en la Fase 2: solicitud de eliminación desde la app (Superadmin, auditada) procesada por el script; asistencia como condición de acceso. Pendiente: despliegue de reglas; prueba física con Android | 2 ✅ |
| 4 | Gestión de productos | 🟡 | `features/menu` (`Dish`, `MenuCategory`, repositorio, editor, `menu_admin_screen`). Auto: `menu_test`, `menu_repository_errors_test`, `rules.test.js` | Hecho en la Fase 3: fotos reales (Decisión 3), disponibilidad rápida, URL opcional. Pendiente: precio/costo enlazables a recetas (Fase 7); prueba física | 3 ✅ |
| 5 | Carta digital | 🟡 | `public_menu_screen`, `dish_image`, ruta pública `/carta` | Hecho en la Fase 3: fotos reales, ficha del plato, agotados al final; sigue sin login/carrito/pagos. Pendiente: prueba física y revisión visual | 1, 3 ✅ |
| 6 | Gestión de mesas | ✅ | `features/tables` (modelo, repositorio transaccional, servicio, editor, pantalla). Auto: `orders_test`, `reservations_test` | Hecho en la Fase 4: el mosaico muestra «Reservada HH:mm · cliente». Pendiente: liberación por pago (Fase 6); prueba física | 4 ✅, 6 |
| 7 | Gestión de pedidos | ✅ | `features/orders` + `features/waiters` (apertura, ítems, transiciones, política de edición, pedidos propios, cancelación con motivo, estado de cocina). Auto: `orders_test`, `orders.rules.test.js` | Hecho en las fases 4 y 5: cancelación con motivo y autor; flujo hacia cocina (registrar → pendiente en cocina). Pendiente: pago y cierre (Fase 6); prueba física | 4 ✅, 5 ✅ |
| 8 | Cocina | 🟡 | `features/kitchen` (`KitchenScreen`, `KitchenPolicy`), `KitchenStatus` y `advanceKitchen` en `features/orders`. Auto: `kitchen_test`, `orders.rules.test.js`, `permissions.rules.test.js` | Hecho en la Fase 5: tablero por estados (pendiente, en preparación, listo), tiempos de espera con urgencia, entrega por el mesero, reglas. Pendiente: aviso sonoro, impresión de tickets, consulta por estado; prueba física en tablet | 5 ✅ |
| 9 | Caja y ventas | ✅ | `features/cashier` (modelos, repositorio transaccional, servicio, pantallas con navegación vertical propia). Auto: `cashier_test`, `caja.rules.test.js` | Hecho en la Fase 6. Pendiente: anulaciones/devoluciones con auditoría, comprobantes; prueba física | 6 ✅ |
| 10 | Inventario | ✅ | `features/inventory` (insumos, movimientos de stock, alertas de stock bajo). Auto: `inventory_test`, `inventario.rules.test.js` | Hecho en la Fase 7. Pendiente: descuento automático por venta; prueba física | 7 ✅ |
| 11 | Recetas y costos | 🟡 | `recetas/{platoId}`, pestaña Recetas (costo por porción y margen) | Hecho: receta y costo. Pendiente: descuento de stock al vender | 7 ✅ |
| 12 | Proveedores y compras | ✅ | `proveedores`, `compras` (pendiente → recibida/cancelada, ingreso atómico a stock) | Hecho en la Fase 7. Pendiente: pagos a proveedores, adjuntos | 7 ✅ |
| 13 | Reservaciones | 🟡 | `features/reservations` (modelo, repositorio, servicio, pantalla, editor), colección `reservaciones`. Auto: `reservations_test`, `reservations.rules.test.js`, `permissions.rules.test.js` | Hecho en la Fase 4: reservas por mesa y horario (hora de Lima), estados pendiente → confirmada → cumplida / cancelada (con motivo) / no asistió, «Sentar y abrir pedido». Pendiente: bloqueo del cruce de horarios a nivel de reglas; avisos al cliente; prueba física | 4 ✅ |
| 14 | Reportes y estadísticas | ✅ | `features/reports` (ventas, platos, asistencia, inventario/costos por periodo; solo Admin y Superadmin). Auto: `reports_test`, `reportes.rules.test.js` | Hecho en la Fase 8. Pendiente: exportar CSV/PDF, comparar periodos, gráficos, indicadores en el dashboard; prueba física | 8 ✅ |
| 15 | Configuración y auditoría | 🟡 | `features/audit` (modelo, repositorio, `audit_screen` de solo lectura); auditoría en reglas de personal y terminales | Configuración del negocio; auditoría en todos los módulos; filtros | 9 |

## Hoja de ruta por fases

Estado: ⏳ pendiente · 🔄 en curso · ✅ completada.

| Fase | Alcance | Estado |
|------|---------|--------|
| **0** | Auditoría integral y planificación (este README) | ✅ 2026-11-12 |
| **1** | **Diseño visual global:** tema claro azul/blanco (sin predominio oscuro), tokens de color/tipografía/espaciado, logotipo con el plato, componentes reutilizables (tarjeta, tabla, estados vacío/error/carga, formularios), navegación responsiva PC/tablet/celular sobre `StaffShell`, reemplazo de `ModulePlaceholder` por un «módulo en preparación» con marca, dashboard base. Sin lógica de negocio nueva. **Rehecha según la referencia visual** | ✅ 2026-11-12 (pendiente revisión visual) |
| **2** | **Autenticación, permisos, personal y asistencia:** permisos por acción en Flutter y reglas con prueba de alineación; pantalla Roles; **asistencia como condición de acceso operativo** junto al rol; cerrar eliminación definitiva de terminales (decisión 1); checklist de prueba física; despliegue de reglas solo con autorización | ✅ 2026-11-18 (sin desplegar ni probar físicamente) |
| **3** | **Productos y carta digital:** fotos reales (decidir almacenamiento en Spark), ficha de plato, disponibilidad, carta pública con la nueva identidad | ✅ 2026-11-18 (sin desplegar ni probar físicamente) |
| **4** | **Mesas, pedidos y reservaciones:** completar lo existente, módulo de reservaciones, reglas y pruebas | ✅ 2026-11-19 (sin desplegar ni probar físicamente) |
| **5** | **Cocina:** cola de pedidos, estados, tiempos, tablero para tablet | ✅ 2026-11-19 (sin desplegar ni probar físicamente) |
| **6** | **Caja y ventas:** cobro, cierre de caja, ventas, liberación de mesa | ✅ 2026-11-19 |
| **7** | **Inventario, recetas, costos, proveedores y compras** | ✅ 2026-11-19 · **aceptada por el propietario; validada automáticamente, pendiente de pruebas físicas y Firebase real** (`docs/CHECKLIST_FISICO_FASE_7.md`) |
| **8** | **Reportes y estadísticas** sobre datos reales de las fases 2–7 | ✅ 2026-11-19 (sin desplegar ni probar físicamente) |
| **8B** | **Descuento automático de inventario al marcar «Listo» en Cocina** (fase independiente, posterior a la 8; ver «Fase 8B» abajo) | ✅ hecha en código y pruebas automatizadas; sin desplegar ni prueba física |
| **9** | **Configuración y auditoría** transversal | ⏳ |
| **10** | **Integración y validación general:** suite completa, reglas completas, `flutter analyze`, revisión de identidad visual, pruebas físicas, preparación de despliegue | ⏳ |

## Decisiones técnicas

1. **Eliminación definitiva de terminales sin Cloud Functions:** las reglas no pueden borrar cuentas de Authentication (`allow delete: if false`). El trabajo en curso es un script local con Admin SDK (`tools/delete_terminal.js`: simulación por defecto, `--execute` con confirmación, clave de servicio fuera del repositorio, conserva asistencias y auditoría) al que se pasa el UID. **Cerrado en la Fase 2:** la app registra una **solicitud** (`solicitudesEliminacionTerminal/{uid}`, solo Superadmin, solo con la terminal inhabilitada, auditada en el mismo lote; reactivar la terminal la cancela) y el script la procesa desde el equipo del propietario, sin credenciales en la app: `--pendientes` lista las solicitudes y sin solicitud el script se niega (`--sin-solicitud` es la excepción manual). Al terminar borra también la solicitud.
2. **Asistencia y acceso (decidido por el propietario, implementado en la Fase 2):** condición adicional al permiso del rol, verificada en reglas (`onShift()`: `estadoAsistencia/{uid}.abierta == true`) y reflejada en Flutter (`Authenticated.onShift`, `RoleNavigation`, `AuthRedirect`). **Superadmin y Admin están exentos.** Mesero, Cocina y Cajero necesitan la entrada registrada para sus módulos operativos (mesas, pedidos, mesero, cocina, caja, insumos, utensilios) y **pierden el acceso al registrar la salida**, en vivo. «Mi asistencia» siempre está disponible. Límite: no hay cierre automático de jornada; quien olvida marcar la salida conserva el acceso hasta que se regularice.
3. **Fotos de platos (decidido en la Fase 3):** Firebase Storage exige Blaze, así que la foto se guarda **como bytes en Firestore** (`cartaFotos/{platoId}`: `foto`, `tipo: image/jpeg`, `actualizadoEn`), ya reducida por la app a ≤ 90 KB (tope de 100 KB en las reglas, alineado con `DishPhotoCompressor`). La lista de la carta no las carga: cada foto se pide solo al mostrar el plato (`dishPhotoProvider`). `imagenUrl` pasa a ser **opcional** (prioridad: foto → URL → marcador) y se conserva como alternativa gratuita (p. ej. Firebase Hosting o una URL externa) si el tráfico de la carta pública llegara a pesar. Se descartaron los assets empaquetados (cada foto exigiría publicar una versión nueva de la app). El propietario puede vetar esta decisión: es la única que introduce un patrón nuevo (binarios en Firestore).
4. **Sin Cloud Functions:** la lógica va en cliente + reglas + transacciones; lo que no se pueda así se resuelve con herramientas locales de administración.
5. **Convenciones:** repositorio abstracto + implementación Firestore + fake de prueba (`test/support/*_fakes.dart`); rutas nuevas en `AppRoute`; colecciones nuevas en `FirestorePaths`; dinero en centavos.
6. **Permisos por acción:** `PermissionService` guarda la matriz rol → módulo → acciones (`read/create/update/delete/special`) y de ella se derivan los permisos de pantalla (`Permission`). `tools/fixtures/permission_matrix.json` se genera desde Dart (`UPDATE_PERMISSION_MATRIX=1 flutter test test/features/permission_service_test.dart`) y `tools/permissions.rules.test.js` ejecuta cada celda contra las reglas reales. La pantalla Roles es de **solo lectura** a propósito: la matriz está en código y reglas, y editarla desde la app las desalinearía.

## Riesgos y validaciones pendientes

- Cambios locales de reglas sin desplegar (incluye la condición de asistencia y `solicitudesEliminacionTerminal`); el despliegue requiere autorización. Hasta entonces, con Firebase real la app **no** tendría las reglas nuevas y la pantalla de solicitud fallaría por permisos.
- Sin pruebas físicas (Android con QR, Firebase real) para las fases históricas 3–5 ni para la Fase 2 (`docs/CHECKLIST_FISICO_FASE_2.md`).
- Trabajo de las fases 1 y 2 y de la eliminación de terminales sin commit en la rama `Isra`.
- Matriz de permisos duplicada (Dart y reglas): mitigado con `permissions.rules.test.js`, que cubre las celdas con colección propia. Las celdas de Dashboard, Roles y Reportes (que leen con las reglas de cada módulo; ver `reportes.rules.test.js`) solo se aplican en Flutter hasta que tengan colecciones (el test falla si aparece una celda nueva sin clasificar).
- Jornada sin cierre automático (ver Decisión 2) y sin rate limiting ni App Check (límites de Spark).
- **Pruebas físicas (intento del 2026-11-19): 0 de 54 pasos ejecutados** (fase 2: 22, fase 3: 13, fase 4: 19; todos *bloqueados*). Motivo: sin dispositivo Android ni emulador, sin cuentas de prueba ni clave de servicio, y reglas sin desplegar (no autorizado). Solo se comprobaron las compilaciones: `flutter build web --release` y `flutter build apk --debug` aprobadas. Qué se necesita para desbloquear cada fase: al final de `docs/CHECKLIST_FISICO_FASE_2.md`, `_3.md` y `_4.md`.
- **Inventario (Fase 7), auditoría de seguridad del 2026-11-19: hallazgos corregidos el mismo día en reglas, modelos, repositorio y pruebas (ver «Corrección de seguridad de la Fase 7» en el registro de la Fase 7); verificación en Firebase real pendiente.** Los hallazgos eran: reescribir el stock con un movimiento histórico; usar la recepción de una compra para sumar/restar stock de cualquier insumo y fijar costos; recibir sin movimientos; compras con líneas basura; costo cambiado en entradas manuales; `proveedorNombre` falso; recepción por quien creó la compra. **Límites que siguen abiertos:** (a) el **máximo de 8 líneas por compra es provisional**: el emulador no aplica el límite de accesos a documentos de producción (10 por operación y 20 por lote/transacción), y una recepción de 8 líneas toca unos 20 documentos distintos (perfil, asistencia, compra, 8 movimientos y 8 insumos; estimación, no medida), justo en el tope de 20 por lote; hay que **probarla en Firebase real** y, si falla, bajar el máximo (`InventoryValidation.maxLines` y las reglas `validPurchase`/`purchaseFullyMoved`); (b) por el límite de **1000 expresiones por evaluación** de las reglas, al **crear** una compra no se consulta cada insumo: el insumo (existente, activo, mismo nombre en el movimiento) se exige **al recibir**, así que una compra con insumo inexistente puede crearse pero no recibirse (solo cancelarse); el `nombre` de la línea es informativo y no se contrasta; (c) una línea con cantidad > 10⁹ o costo > S/ 100 000 puede crearse pero no recibirse; (d) quien tenga Admin/Superadmin sigue pudiendo recibir su propia compra y cambiar costos de insumos a mano (por diseño).
- Inventario (Fases 7 y 8B): sin pruebas físicas ni Firebase real; el descuento automático (8B) **bloquea «Listo» si falta stock** (Admin y Superadmin pueden forzarlo con motivo; ver «Excepción de Admin»), y el máximo de 8 insumos distintos por pedido es provisional (ver Fase 8B).
- Cocina: la pantalla escucha todos los pedidos y filtra en la app (como el resto de las pantallas de pedidos); con mucho historial conviene una consulta por estado. No hay aviso sonoro ni impresión de tickets. Decisión a confirmar por el propietario: **Admin y Superadmin también operan la cocina** (módulo `kitchen` con ver y editar; antes solo Cocina), para poder destrabar un ticket; Cocina no entrega y el mesero no mueve la cocina.
- Reservaciones: las reglas no pueden consultar otras reservas, así que el cruce de horarios de una misma mesa (2 h por reserva) solo lo avisa la app; dos altas simultáneas podrían coincidir. Alternativa si hiciera falta: documento «candado» por mesa y bloque horario.
- Cancelaciones de pedido y de reserva guardan motivo y autor en el propio documento, no en `auditoria` (esa colección solo la escribe el Admin y solo la lee el Superadmin; ver Fase 9).
- Fotos en Firestore: cada visita a la carta descarga ~40–90 KB por plato mostrado; revisar el uso de Firestore (cuotas Spark) tras publicar (checklist de la Fase 3, paso 13). Una foto cambiada no se actualiza en una carta ya abierta hasta recargar.
- Cada comprobación de acceso operativo añade una lectura de `estadoAsistencia` por petición en las reglas (dentro del límite de 10/20 accesos por petición).

## Fase 8B — Descuento automático de inventario (hecha el 2026-11-19)

Al pasar un pedido de «Preparando» a «Listo» en Cocina, **en la misma transacción** se descuenta del inventario lo que consume (receta de cada plato × cantidad pedida, acumulado por insumo).

1. **Un único descuento por pedido:** el documento `descuentosInventario/{pedidoId}` es de solo creación (las reglas prohíben actualizarlo o borrarlo) y el paso a «Listo» exige que se cree en el mismo lote; un segundo intento (otro cocinero, reintento o corte) falla. Dos cocineros a la vez: solo uno confirma.
2. **Una sola transacción:** `FirestoreOrderRepository.advanceKitchen` lee recetas e insumos con `tx.get`, calcula con `ConsumptionPlanner` y escribe marcador, movimientos, stock y estado juntos. Si algo falla (stock, reglas, concurrencia) no cambia nada. Las reglas obligan a que el pedido solo pase a «Listo» si el marcador y los movimientos de todas sus líneas existen en el lote (`consumptionDone`).
3. **Sin stock negativo:** si un insumo no alcanza, la transición se rechaza con «No hay stock suficiente de «X»: el pedido necesita A y hay B» y no se descuenta nada. Las reglas también exigen `stock ≥ 0`.
4. **Auditoría:** un movimiento `consumo` por insumo (id `{pedido}_{n}`, insumo, cantidad negativa, stock resultante, `pedidoId`, responsable uid y nombre, hora del servidor) más el marcador (n.º de insumos, platos sin receta, insumos omitidos, responsable y hora). Los movimientos de consumo aparecen en la pestaña Movimientos con «Pedido {id}».
5. **Sin devolución automática:** ningún camino de código ni de reglas repone stock al cancelar (un consumo positivo se rechaza); la reposición es un **ajuste manual con motivo** de Cocina o la administración.

**Decisiones de diseño:**
- *Platos sin receta:* no descuentan; se cuentan en `platosSinReceta` del marcador. *Insumos inexistentes o desactivados* en una receta: se omiten y se cuentan en `insumosOmitidos`.
- *Permisos:* Cocina (con jornada) y Admin/Superadmin pueden escribir; Cocina **lee** `insumos` y `recetas` (necesario para calcular; ve el costo) pero solo toca el stock con un movimiento `consumo` ligado al pedido y no ve movimientos ni descuentos. La matriz de `PermissionService` no cambia (no hay módulo nuevo).
- *Orden de lectura:* los platos del pedido (inmutable tras registrarse) se leen antes de la transacción; recetas e insumos, dentro.
- Caja no se tocó.

**Excepción de Admin/Superadmin: forzar «Listo» con stock insuficiente (añadida el 2026-11-19).**
- *Flujo:* Cocina no cambia: si falta stock sigue viendo el rechazo. Si quien pulsa «Marcar listo» es Admin o Superadmin, la app muestra «Falta stock» con los faltantes (insumo, necesario, disponible, faltan) y pide un **motivo de 10 a 200 caracteres** (se recorta; con menos de 10 caracteres reales no deja). Al confirmar, la **misma transacción** descuenta **solo lo disponible** (cada insumo baja como mucho hasta 0; un insumo en 0 no genera movimiento), marca «Listo» y guarda la excepción. Si no falta nada, forzar no hace nada especial (no se registra excepción).
- *Auditoría independiente:* `excepcionesInventario/{pedidoId}` (solo creación; solo lectura Admin/Superadmin): motivo, **faltantes** (`insumoId`, `insumo`, `necesario`, `descontado`, `faltante`; hasta 8), usuario (uid y nombre), hora del servidor; el pedido es el id del documento. El marcador `descuentosInventario/{pedido}` lleva `forzado: true`.
- *Reglas:* la excepción solo la crea `isAdmin()` junto al paso preparando→listo (comprueba `getAfter` del pedido y del marcador); el marcador con `forzado: true` exige `isAdmin()` y que la excepción exista en el mismo lote, y la excepción exige el marcador forzado (no hay una sin la otra). Motivo ≥ 10 caracteres reales, faltantes con `necesario = descontado + faltante`, `faltante > 0`, 1 a 8. El stock sigue sin poder quedar negativo y el consumo solo resta (un consumo mayor al stock ya fallaba por `stockResultante ≥ 0`). Un solo descuento por pedido: el marcador (mismo id) es de solo creación, así que un segundo intento, forzado o no, falla; la excepción tampoco se edita ni se borra.
- *Límite de lote:* un forzado a 8 insumos toca unos 20 documentos (19 sin la asistencia, que Admin no consulta, más la excepción): en el tope de 20 de producción; **validar en Firebase real**.
- *Límite de confianza:* las reglas no pueden comprobar que los faltantes y cantidades sean los de la receta (como el descuento normal): un Admin con cliente alterado podría registrar una excepción distinta de la real o forzar sin marcar `forzado` (descontando menos). La excepción es auditoría, no un control.

**Límites y puntos abiertos:**
- **Las cantidades las calcula el cliente** (no hay Cloud Functions) y las reglas **no pueden recorrer recetas** (límite de accesos): validan coherencia (stock = anterior + delta, nunca negativo, consumo negativo, vínculo con el pedido, un descuento por pedido), no que la cantidad coincida con la receta. Un cliente alterado con rol Cocina/Admin podría descontar menos o más (siempre dentro del stock) de lo que dice la receta.
- **Máximo 8 insumos distintos por pedido** (provisional): una recepción de ese tamaño toca unos 20 documentos, en el tope de 20 por lote de producción, que el emulador **no aplica**. Un pedido que necesite más no se puede marcar «Listo» hasta que la administración simplifique recetas o se amplíe el límite tras medir en Firebase real.
- **Si falta stock, Cocina queda bloqueada** en ese pedido hasta que reponga Cocina o un Admin/Superadmin fuerce el «Listo» con motivo (ver arriba).
- Un pedido que **ya estaba «Listo» antes de esta fase** no descuenta; los que estaban «Preparando» al desplegar descuentan al marcarse.
- Hay que **desplegar las reglas** (con autorización) y probar en Firebase real (checklist `docs/CHECKLIST_FISICO_FASE_8B.md`).

**Pendientes explícitos de la Fase 8B (la Fase queda aceptada solo a nivel de pruebas automáticas):**
1. **Validar la transacción desde la aplicación contra Firebase real.** `FirestoreOrderRepository.advanceKitchen` / `_deductInventory` (lecturas con `tx.get`, marcador, movimientos, stock, excepción y estado en una sola transacción) **no tiene prueba automática**: las pruebas cubren el planificador (`ConsumptionPlanner`), el servicio, el diálogo y las reglas por separado, pero nunca la app real contra Firestore real. Hay que ejecutar los pasos 1 a 19 del checklist con las reglas desplegadas (requiere autorización del propietario): descuento normal, concurrencia de dos cocineros, falta de stock, forzado con motivo y que los permisos de cada rol se comporten como en el emulador.
2. **Probar el límite de 8 insumos y de accesos por lote en Firebase real.** El emulador **no aplica** el tope de producción (10 accesos por operación, 20 por lote/transacción); un pedido de 8 insumos toca unos 20 documentos (un forzado con excepción, también ~20: 19 sin la asistencia de Admin + la excepción). Es una estimación, no una medida. Hay que probar en Firebase real un pedido de 8 insumos (normal y forzado) y uno de 9 (debe rechazarlo la app). Si falla con `permission-denied`, bajar `ConsumptionPlanner.maxSupplies` y las reglas (`consumptionDone`, `validShortages`, tope de `insumos` del marcador) y repetir; el mismo criterio vale para las líneas de compra de la Fase 7.
3. **Limitación de las reglas: no pueden verificar que cantidades y faltantes coincidan con la receta.** Recorrer recetas e insumos de cada plato excede el límite de accesos y de 1000 expresiones por evaluación, así que las reglas solo validan coherencia: stock = anterior + delta, nunca negativo, consumo solo resta, vínculo con el pedido, un descuento por pedido, y en la excepción `necesario = descontado + faltante`, motivo ≥ 10 caracteres, usuario y hora. Quien tenga rol Cocina/Admin con un cliente alterado podría descontar más o menos que la receta (dentro del stock), y un Admin podría registrar faltantes distintos de los reales o forzar sin marcar `forzado`. El descuento y la excepción son **auditoría con trazabilidad**, no un control preventivo; el cálculo correcto depende de la app. La contrapartida es revisar periódicamente los movimientos `consumo` y `excepcionesInventario`.

## Registro de fases

| Fase | Completado | Pendiente | Pruebas |
|------|-----------|-----------|---------|
| 0 | Auditoría y este plan; sin cambios de código | — | No aplican (sin cambios de código) |
| 1 | **Rehecha (2026-11-12) siguiendo `docs/referencias/diseno.jpeg`.** *Sistema:* paleta de la referencia (`AppColors`: azul marino de encabezados, azul intenso `#1C5FD4` en acciones, fondo `#F3F6FB`, etiquetas de estado verde/amarillo/rojo suaves); tema único claro (`AppTheme.light`, sin tema oscuro); AppBar azul marino, pestañas con subrayado azul, tablas, campos y botones restilizados. *Marca:* logotipo tipográfico «LA GRANJA AZUL / RESTAURANTE» en blanco con punto amarillo (`BrandWordmark`) sobre degradado azul marino (`BrandBackdrop`, con el plato `assets/images/plato.png` (recorte de `docs/referencias/plato.png`) grande, saliendo por el borde derecho y difuminado hacia el azul marino, con animación (entrada, flotación suave y resplandor azul; respeta «reducir animaciones»; `core/widgets/motion.dart`: `Interactive` = crece al pasar el cursor y se hunde al presionar, usado en el botón «Ingresar», filtros y platos; `Reveal` = aparición escalonada de la tarjeta de acceso y los platos). Las animaciones aún no se aplican a mesas, pedidos ni indicadores); se retiró el plato dibujado de la primera versión. *Componentes (`core/widgets`):* `StatusPill`, `StatCard`, `PanelCard`, `FilterPill`, `PageBody`, `SectionHeader`, `StateMessage`. *Navegación (`StaffShell`):* panel lateral azul marino con logotipo, ítem activo en azul intenso y usuario al pie (escritorio ≥ 840 dp, extendido; tablet 600–839, solo iconos), barra superior blanca con título/usuario/salir; celular = encabezado azul marino con cajón. *Pantallas rehechas:* acceso y recuperación/verificación (`CenteredCard`: encabezado azul + tarjeta que lo solapa, «Iniciar sesión», botón «Ingresar»), dashboard (indicadores reales de pedidos y mesas + tabla «Últimos pedidos»), carta pública (encabezado «Nuestra Carta», filtros por categoría, platos con foto, precio azul y etiqueta de disponibilidad), mesas (mosaicos verde/rojo/gris), pedidos (tarjetas con etiqueta de estado), administración de carta (miniatura de foto), marcadores de módulos. Resto de pantallas (usuarios, personal, restricciones, asistencia, terminales, auditoría) heredan el tema pero **conservan su disposición anterior**. Sin cambios de lógica, rutas ni permisos. | **No hecho:** (a) fotografías reales de cada plato — solo está la foto del plato de marca en los encabezados; los platos de la carta muestran un marcador azul si su `imagenUrl` está vacía o no carga (decisión de fotos en Fase 3); (b) indicadores de ingresos/reservas, gráfico de ventas, pestañas Comedor/Terraza y estado «Reservada» de la referencia: dependen de datos que aún no existen (Caja, Reservaciones, zonas de mesa); (c) «Recordar sesión» del acceso: no hay lógica; (d) pantallas de usuarios, personal, asistencia, terminales, restricciones y auditoría sin rediseño de disposición (tablas/tarjetas como en la referencia); (e) pantalla de cámara de la terminal y vista de QR sin rediseño; (f) contraste y tamaños de texto sin auditoría de accesibilidad; (g) revisión visual real. | `flutter analyze lib` y `login_flow_test` (incluye prueba de navegación a 390/800/1280 px sin desbordes, actualizada al nuevo panel); `menu_test`, `activation_test`, `email_and_welcome_test`, `orders_test`, `session_and_reset_test`. La corrida detectó un desborde real en la tarjeta de plato; se corrigió y se repitieron solo `menu_test` y `activation_test` (pasan). **No ejecutadas:** suite completa, reglas Firestore, asistencia/personal (no se tocó su código). **Pendiente:** prueba física/visual en celular, tablet y PC y comparación con la referencia. |
| 2 | **Hecha el 2026-11-18** (decisión del propietario: Superadmin y Admin exentos de la asistencia; el resto necesita entrada y pierde el acceso con la salida). *Permisos:* `Permission` ahora equivale a (módulo, acción); `PermissionService` guarda la matriz rol → módulo → acciones (15 módulos, 5 acciones) y deriva de ella los permisos de pantalla sin cambiar ninguno (hay prueba). Nadie tiene `delete`: el histórico se conserva. *Pantalla Roles:* matriz de solo lectura por rol con su condición de asistencia (sustituye al marcador). *Asistencia como condición:* reglas `onShift()` (Admin/Super exentos; el resto con `estadoAsistencia.abierta`) aplicada a `mesas` y `pedidos`(+detalles); `sessionProvider` sigue `estadoAsistencia` en vivo (`Authenticated.onShift`, fallo = jornada cerrada); `AppRoute.requiresShift`, `RoleNavigation` y `AuthRedirect` esconden y bloquean los módulos operativos sin jornada; «Mi asistencia» siempre disponible, con aviso. `_accountSession` se reescribió con suscripciones manuales (el `switchMap` anidado no propagaba un cierre de sesión en las pruebas de widgets). *Eliminación de terminales:* solicitud desde la app (`solicitudesEliminacionTerminal`, regla, auditoría `solicitar_eliminacion_terminal`, estado y menú en Terminales; reactivar cancela) y `delete_terminal.js` con `--pendientes`, exigencia de solicitud y limpieza de la solicitud al terminar. *Documentación:* `docs/CHECKLIST_FISICO_FASE_2.md`. | **No hecho:** (a) despliegue de reglas (requiere su autorización); (b) prueba física con Firebase real y Android (checklist); (c) permisos por acción aplicados a pantallas distintas de las rutas (los botones de cada pantalla siguen controlados por rol/regla, no por la matriz); (d) edición de la matriz desde la app (descartado por diseño); (e) cierre automático de jornada; (f) editar documento/correo de un trabajador; (g) las celdas de Dashboard, Roles, Cocina, Caja, Inventario y Reportes no tienen colección en reglas todavía; (h) `ESTADO_PROYECTO.md` sigue siendo histórico y no refleja esta fase. | **Ejecutadas:** `flutter analyze` (completo, sin problemas); Flutter: `permission_service_test` (matriz, derivación, exención, fixture), `auth_redirect_test` (jornada), `login_flow_test` (ampliada: sin entrada, entrada y salida en vivo, exentos), `terminals_screen_test` (solicitud), `roles_screen_test` (nueva), `session_and_reset_test`, `activation_test`, `attendance_test`, `phase3_widgets_test`, `staff_test`, `orders_test` (por tocar sesión, navegación y fakes). Reglas y herramientas, **suite completa** (`npm run test:rules`, por tocar `firestore.rules`): **263 pruebas OK**, incluidas las nuevas `permissions.rules.test.js` (cada celda de la matriz × 6 roles contra las reglas, jornada abierta/cerrada/inexistente, salida en vivo, solicitud de eliminación) y 2 pruebas CLI + 1 de proceso en `delete_terminal.test.js`; `orders.rules.test.js` se actualizó para sembrar la jornada. **No ejecutadas:** `flutter test` completo (no se tocó menú, carta ni correos); `flutter build`. **Pendiente:** prueba física (checklist) y despliegue. |
| 3 | **Hecha el 2026-11-18.** *Fotos:* decisión 3 (bytes en Firestore, ver arriba). `DishPhotoCompressor` reduce cualquier foto (JPG/PNG/WebP) a un JPEG ≤ 90 KB probando lados 800→360 px y calidades 80→40, aplica la orientación EXIF y quita la transparencia; `DishPhotoPicker` (image_picker: galería en Android, selector de archivos en la web) está detrás de una interfaz; `DishPhotoRepository` + `FirestoreDishPhotoRepository` guardan, leen y quitan; `DishImage` muestra foto → URL → marcador. Editor de platos: elegir/cambiar/quitar foto con vista previa y aviso de proceso; el plato se guarda primero y luego la foto (las reglas exigen que exista), y si la foto falla el plato queda guardado y «Guardar» reintenta. Los platos nuevos reciben su id en el cliente (`MenuService.newDishId`) para poder asociar la foto. *Reglas:* `cartaFotos` (lectura pública; solo admin/superadmin activos escriben, solo JPEG ≤ 100 KB, campos exactos, hora del servidor, plato existente; borrar = quitar la foto) y `imagenUrl` opcional (vacía o HTTPS). *Disponibilidad:* interruptor en la lista de administración (guarda al instante), y en la carta pública los agotados van al final de su categoría, atenuados y con «No disponible». *Ficha del plato:* al tocar un plato de la carta pública se abre la ficha (foto grande, descripción completa, precio y disponibilidad). *Dependencias nuevas:* `image_picker`, `image`. *Documentación:* `docs/CHECKLIST_FISICO_FASE_3.md`. | **No hecho:** (a) prueba física con el selector real, Firebase real y Android (checklist); (b) despliegue de reglas (requiere su autorización); (c) fotos con actualización en vivo en cartas ya abiertas; (d) varias fotos por plato y recortado manual; (e) precio/costo enlazados a recetas (Fase 7); (f) auditoría de cambios de la carta (Fase 9); (g) medir el consumo real de Firestore con fotos. | **Ejecutadas:** `flutter analyze` (completo, sin problemas); `flutter build apk --debug` (compila con los plugins nuevos); Flutter: `dish_photos_test` (nueva: compresor, editor, administración, carta pública) y `menu_test` + `menu_repository_errors_test`; reglas: `rules.test.js` (25 OK, con 4 pruebas nuevas de `cartaFotos` y URL opcional). **No ejecutadas:** suite completa de Flutter y de reglas (no se tocaron sesión, permisos ni pedidos; los demás archivos de reglas no usan `carta`/`cartaFotos`); `flutter test` web. **Pendiente:** prueba física (checklist) y despliegue. |
| 4 | **Hecha el 2026-11-19.** *Revisión previa:* mesas, pedidos y su estructura (`docs/FASE_5.md` histórico) ya existían y se conservaron; no se duplicó nada. *Pedidos:* la cancelación exige motivo (3–200 caracteres) y deja `canceladoPor`; `OrderRepository.cancelOrder` separado de `changeStatus` (que solo registra); diálogo de motivo; el detalle muestra el motivo; reglas: los campos solo existen en pedidos cancelados y `canceladoPor` = quien cancela. *Reservaciones (nuevo):* `reservaciones/{id}` (mesa, cliente, teléfono, personas, fecha/hora, notas, estado, quién la registró, `pedidoId`/`motivoCancelacion` opcionales); estados pendiente → confirmada → cumplida (enlaza el pedido de esa mesa) / cancelada (motivo) / noAsistio (solo pasada la hora), finales inmutables, sin borrado; rol: Admin, Superadmin y Mesero con jornada abierta crean y gestionan, Caja solo consulta; reglas validan mesa activa, capacidad y fecha futura; la app valida formato, cruce de horario (2 h por mesa) y orquesta «Sentar y abrir pedido»; pantalla con vistas Hoy / Próximas / Historial, editor con fecha y hora de Lima, y «Reservada HH:mm» en el mosaico de la mesa. Nuevo módulo `AppModule.reservations`, permisos `viewReservations` y `manageReservations`, ruta `/app/reservaciones` (exige jornada abierta), matriz y fixture regenerados. *Documentación:* `docs/CHECKLIST_FISICO_FASE_4.md`. | **No hecho:** (a) bloqueo del cruce de horarios en reglas (límite de Firestore, ver riesgos); (b) avisos o recordatorios al cliente (WhatsApp/SMS); (c) reserva pública desde la carta (la carta sigue sin pedidos ni reservas públicas); (d) zonas Comedor/Terraza; (e) indicador de reservas en el dashboard; (f) motivo/autor de cancelaciones en `auditoria` (Fase 9); (g) prueba física y despliegue de reglas. | **Validación integral (2026-11-19):** `flutter analyze` completo: sin incidencias (corrida inicial: 3 avisos de estilo causados por mi `dart format lib`; se corrigieron con llaves y, tras la limpieza posterior, 2 de esos archivos se restauraron a `HEAD`); `flutter test` **completo: 261 aprobadas** (incluye 24 nuevas de `reservations_test`, 3 de cancelación en `orders_test`, matriz de permisos y todas las fases 1–3); reglas Firestore, suite **completa** con emulador (`npm run test:rules`: **320 pruebas**: reglas de carta/fotos, personal, asistencia, terminales, restricciones, pedidos y mesas, permisos por celda de la matriz, nuevas de reservaciones) — 319 aprobadas y 1 fallo en una prueba nueva mía de `orders.rules.test.js` (usaba dos instancias de Firestore en una transacción; error de la prueba, no de las reglas), corregida y repetida solo `orders.rules.test.js`: 18/18. Tras agregar las llaves se repitieron solo `attendance_test` y `phase3_widgets_test` (63 aprobadas). **No ejecutadas:** `flutter build` (esta fase no añade plugins ni cambia configuración nativa; el APK se compiló en la Fase 3); pruebas en dispositivo o navegador reales; Firebase real (producción). **Efecto colateral (resuelto el 2026-11-19):** por error ejecuté `dart format lib`, que reformateó archivos de otras fases. Análisis posterior (comparando cada archivo con `HEAD` ya formateado): 41 archivos eran solo formato y 2 solo llevaban las llaves que agregué (43 en total, sin ningún cambio funcional); con autorización del propietario se restauraron exactamente esos 43 con `git restore`. Los 49 archivos `.dart` con cambios funcionales de las fases 1–4 conservan sus cambios (un informe previo decía 51 porque contaba también los 2 de solo llaves); algunos llevan además formato mezclado, que no se puede separar sin riesgo y se dejó. No se tocó ningún archivo nuevo, recurso, regla ni prueba. Tras la limpieza se repitieron `flutter analyze` y las pruebas de asistencia y personal |
| 5 | **Hecha el 2026-11-19.** *Revisión previa:* pedidos, mesas, reservaciones, permisos y asistencia ya existían y se reutilizaron; `KitchenScreen` era un marcador. *Estados:* un pedido registrado entra a cocina como `pendiente` y avanza en línea `pendiente → preparando → listo → entregado`, sin saltos ni retrocesos; los pedidos abiertos o cancelados no entran; un pedido registrado antes de la fase (sin el campo) cuenta como pendiente. Cocina (y Admin/Superadmin) preparan y marcan listo; entrega el mesero responsable o la administración. Cada paso guarda su hora del servidor (`registradoEn`, `preparandoEn`, `listoEn`, `entregadoEn`) y `cocinaPor`. *Reglas:* `validKitchenUpdate` (solo cambia el estado de cocina y su hora, revisión +1, el pedido sigue inmutable en lo demás; cocina y mesero exigen jornada abierta, admin exento); registrar exige `estadoCocina: pendiente` y `registradoEn` = hora del servidor; los campos de cocina solo existen en pedidos registrados. *App:* `KitchenStatus` y `RestaurantOrder` (campos de cocina), `OrderRepository.advanceKitchen` (transacción que rechaza un paso ya dado por otro usuario), `OrderService.advanceKitchen`, `KitchenPolicy` (quién mueve, cola ordenada, minutos de espera, urgencia a los 15 y 30 min), `KitchenScreen` (3 columnas desde 720 px de ancho, una columna con filtros en celular, tickets con detalle y observaciones, reloj que se actualiza cada 30 s), «Cocina: …» y «Marcar entregado» en el detalle del pedido y en la lista de pedidos. Matriz de permisos y fixture regenerados (módulo `kitchen` para Admin y Superadmin). *Documentación:* `docs/CHECKLIST_FISICO_FASE_5.md`. | **No hecho:** (a) aviso sonoro y impresión de tickets; (b) consulta de Firestore por estado en vez de filtrar en la app; (c) tiempos de preparación promedio y reportes (Fase 8); (d) cancelar o devolver un ticket desde cocina; (e) prueba física en tablet y despliegue de reglas; (f) liberar la mesa al entregar (le corresponde a Caja, Fase 6). | **Ejecutadas:** `flutter analyze` completo: sin incidencias; `flutter test` **completo: 282 aprobadas** (21 nuevas de `kitchen_test`: modelo, política, servicio, pantalla ancha y angosta, entrega desde el detalle); reglas Firestore, suite **completa** (`npm run test:rules`): **343 aprobadas** (14 nuevas de cocina en `orders.rules.test.js`, celda `kitchen.update` contrastada contra la matriz y la condición de asistencia en `permissions.rules.test.js`). *Se corrigió:* (1) `OrderService.advanceKitchen` lanzaba el error de forma síncrona (la prueba lo detectó): ahora es `async`; (2) una prueba de reglas mía usaba un valor que no cambiaba nada (`detalleModificado`): se corrigió la prueba, no las reglas; (3) un error de escape en la pantalla de cocina recién escrita se corrigió antes de compilar. **No ejecutadas:** `flutter build` (la fase no añade plugins), tablet y Firebase real. **Pendiente:** prueba física (checklist) y despliegue de reglas. |
| 6 | **Hecha el 2026-11-19.** *Revisión previa:* pedidos, cocina, mesas, permisos y asistencia ya existían y se reutilizaron (el cobro entra por `OrderRepository`/`orderTotal`, sin duplicar); `CashierScreen` era un marcador. *Flujo:* mesero registra → cocina prepara/listo → mesero entrega → **Caja cobra → mesa libre**. Solo se cobra un pedido `registrado` con cocina `entregado`. Nuevo estado terminal `OrderStatus.pagado` (inmutable; conserva los datos de cocina). *Datos:* `pagos/{pedidoId}` (el id del pedido impide el doble cobro), `cajas/{id}`, `cajaActiva/actual` (candado: una sola caja abierta, se crea/borra en el mismo lote que abre/cierra la caja), `movimientosCaja/{id}` (ingresos y egresos). Todo en centavos enteros, con quién operó (uid y nombre) y hora del servidor; solo de agregar: pagos, movimientos y cajas cerradas no se editan ni borran. *Atomicidad:* `FirestoreCashRepository.charge` es una transacción (pago + pedido pagado con revisión +1 + mesa `pedidoActivo: null`); las reglas exigen los tres a la vez (`validPaymentUpdate`, `validTableRelease` con `getAfter/existsAfter`), así que un cobro fallido o interrumpido no libera la mesa y no queda pago suelto. *Reglas:* `canCash()` = cajero, admin o superadmin (jornada abierta salvo exentos); validan método (efectivo/tarjeta/Yape/Plin), vuelto (efectivo ≥ total; el resto exacto), caja abierta, identidad y nombre de quien cobra, hora del servidor, y en el cierre: diferencia = contado − esperado, nota obligatoria si no cuadra, solo quien abrió la caja o un administrador cierra. *App:* `CashService` (valida caja abierta, estado del pedido, efectivo suficiente), pantalla de Caja con **riel vertical propio** (barra inferior en celular): Cobrar, Caja (apertura, ingresos/egresos, cierre con diferencia), Ventas (Hoy / Caja actual / Todas, por método) e Historial de cajas; diálogo de cobro con vuelto en vivo que queda abierto con el motivo si falla. `AppModule.cashier` ahora con crear/actualizar para cajero, admin y superadmin (ven «Caja» en su menú). Dashboard y detalle conocen «Pagado». Matriz y fixture regenerados; `permissions.rules.test.js` ya no declara Caja «sin reglas». *Documentación:* `docs/CHECKLIST_FISICO_FASE_6.md`. | **No hecho:** (a) anular o devolver un cobro, y modificar operaciones cerradas con autorización y auditoría (hoy son inmutables por reglas; el flujo de excepción queda pendiente, la auditoría general es Fase 9); (b) el total del pago lo calcula el cliente: las reglas no pueden sumar subcolecciones, así que un cliente adulterado podría registrar otro total (valida método, vuelto, estado y mesa, no el importe); (c) comprobantes, propinas, división de cuenta, facturación; (d) varias cajas simultáneas; (e) estadísticas, ampliación de roles y planificación (excluidas por instrucción); (f) prueba física y despliegue de reglas. | **Ejecutadas:** `flutter analyze` completo: sin incidencias; `flutter test` **completo: 294 aprobadas** (con 12 de `cashier_test`) y después se añadieron 6 de pantalla a `cashier_test` (ahora **18 aprobadas**, repetido solo ese archivo); `permission_service_test` actualizado y fixture regenerado; reglas con emulador, suite **completa** (`--only firestore`): **370 pruebas, 369 aprobadas**; el único fallo fue `delete_terminal.test.js`, que requiere además el emulador de Auth: repetido con `firestore,auth`: **19/19**. Nuevas: `tools/caja.rules.test.js` (**21**: apertura única, cobro por método, doble cobro y concurrencia, cobros incompletos que no liberan la mesa, estados no cobrables, roles, jornada, inmutabilidad, movimientos, cierre cuadrado y con diferencia, cierre ajeno) y 3 celdas de Caja en `permissions.rules.test.js`. *Se corrigió:* errores de mis pruebas (valores `undefined` en Firestore, intentos lanzados en paralelo, instancias de Firestore mezcladas, depuración que pisó una línea) — ninguno era un defecto de las reglas ni de la app. **No ejecutadas:** `flutter build`, dispositivos y Firebase real. **Pendiente:** prueba física (checklist) y despliegue de reglas con su autorización. |
| 7 | **Hecha el 2026-11-19.** *Revisión previa:* `InventoryScreen` era un marcador; el módulo `AppModule.inventory` (Almacén, Admin y Superadmin con lectura/alta/edición) ya existía, así que **no cambió la matriz de permisos**; se reutilizaron `Money` (Caja), `ErrorMapper`, `OperationButton`, el catálogo de la carta y los componentes de interfaz. *Datos* (cantidades en milésimas de la unidad y costos en centavos, enteros): `insumos` (stock, mínimo, costo, activo; nunca se borran), `movimientosInventario` (solo de agregar: entrada, salida, merma, ajuste, compra, con motivo, stock resultante y autor), `proveedores`, `compras` (hasta 8 líneas tras la corrección de seguridad; pendiente → recibida o cancelada con motivo), `recetas/{platoId}` (ingredientes por porción). *Reglas:* `canStock()`; el stock solo cambia junto a su movimiento (`ultimoMovimiento` + `getAfter`), sin quedar negativo y, en movimientos manuales, con `stock = anterior + delta`; salida/merma/ajuste exigen motivo y signo correcto; recibir una compra exige pasar de pendiente a recibida en el mismo lote (no se recibe dos veces); identidad y hora del servidor en todo. *App:* `InventoryService` (validaciones, sin duplicados, sin stock negativo), `FirestoreInventoryRepository` (transacciones: movimiento de stock y recepción de compra con costo actualizado), pantalla con 5 pestañas (Insumos con filtro de stock bajo, Movimientos, Recetas con costo y margen, Proveedores, Compras). *Documentación:* `docs/CHECKLIST_FISICO_FASE_7.md`. | **No hecho:** (a) **descuento automático de stock al vender o preparar** (las recetas solo calculan costo; la salida por consumo se registra a mano). Hacerlo bien exige un lote por pedido que toque Caja/Cocina y reglas de otros módulos, y sin Cloud Functions recae en el cliente: queda como decisión del propietario; (b) *(resuelto después, ver «Corrección de seguridad de la Fase 7»: las reglas sí validan cada línea desenrollándolas por índice)*; (c) anular una compra ya recibida o revertir un movimiento (hoy se corrige con un ajuste con motivo); (d) pagos a proveedores, adjuntos, lotes y vencimientos; (e) reportes de inventario (Fase 8); (f) prueba física y despliegue de reglas. | **Ejecutadas:** `flutter analyze` completo: sin incidencias; `flutter test` **completo: 317 aprobadas** (17 nuevas de `inventory_test`: cantidades, costos de receta, movimientos, compras, recetas, permisos y pantalla ancha y angosta); reglas Firestore, suite **completa** con emulador de Firestore y Auth (`npm run test:rules`): **428 aprobadas** (16 nuevas de `inventario.rules.test.js` y 2 celdas de inventario en `permissions.rules.test.js`; `delete_terminal.test.js` incluido). *Se corrigió:* un identificador de movimiento reutilizado en una prueba mía, y dos métodos del servicio que lanzaban de forma síncrona (`receivePurchase`, `cancelPurchase`: ahora `async`); una prueba de pantalla necesitó mantener viva la sesión como lo hace el panel real. **No ejecutadas:** `flutter build`, dispositivos y Firebase real. **Pendiente:** prueba física (checklist) y despliegue de reglas con su autorización. |
| 7 (corrección de seguridad) | **Hecha el 2026-11-19, a raíz de la auditoría; sin desplegar.** *Reglas (`firestore.rules`, bloque Fase 7):* (1) **el stock solo cambia con un movimiento NUEVO del mismo lote**: el movimiento debe tener `creadoEn == request.time`, ser del mismo insumo, `stock_nuevo == stock_anterior + delta` y `stockResultante == stock_nuevo`; ya no sirve apuntar `ultimoMovimiento` a un movimiento histórico; el insumo debe estar activo; (2) el **costo del insumo** solo cambia con un movimiento «compra» y toma el costo de su línea; el catálogo solo lo cambia Admin/Superadmin; (3) los movimientos de compra tienen **id fijo `{compraId}_{línea}`**, campos `linea` y `costoUnitario`, y la regla los contrasta con `compras/{id}.lineas[línea]` (mismo insumo, misma cantidad, mismo costo) y con la compra pasando de pendiente a recibida en el mismo lote; el movimiento exige `insumoNombre` igual al del insumo; (4) **recibir exige que existan los movimientos de todas sus líneas** (`getAfter`), y no se puede recibir sin ellos; (5) **separación de funciones:** quien creó la compra no la recibe, salvo Admin y Superadmin; (6) **cada línea se valida** (desenrollada por índice, máximo 8): cantidad entera ≥ 1, costo entero ≥ 0, `subtotal` coherente con cantidad × costo (tolerancia de redondeo de 0,5 centavo), líneas ordenadas por `insumoId` (sin repetidos); el `total` **ya no se guarda** (es la suma de subtotales, derivada en el cliente); `proveedorNombre` debe ser el del proveedor; (7) **toda entrada manual exige motivo** (≥ 3 caracteres), igual que salida, merma y ajuste; (8) los ingredientes de una receta se validan (mapa con `insumoId`, `nombre`, `cantidad` entera ≥ 1). *Cliente:* `PurchaseLine.tryParse`/`RecipeIngredient.tryParse` y `Purchase.fromMap`/`Recipe.fromMap` **ya no lanzan** con datos alterados (descartan lo ilegible; `Purchase.invalidLines` impide recibir); `Purchase.total` es un getter; `createPurchase` ordena las líneas y escribe `subtotal`; `receivePurchase` crea los movimientos con id `{compra}_{n}` y `linea`/`costoUnitario`; `InventoryService.receivePurchase` rechaza al creador (salvo `isAdmin`) y `maxLines` baja a 8; el diálogo de movimiento exige motivo siempre; el costo de un insumo existente es de solo lectura para Almacén. *Pruebas:* los **17 intentos de la auditoría** (A, A2, B, B2, B3, B4, C, D, D2, E, E2, F, G, G2, H, H2 más A3) son pruebas de regresión en `tools/inventario.rules.test.js` (ahora 40 pruebas), con casos de línea inválida, límite de 8 líneas, separación de funciones, movimientos sin stock y viceversa, e ingredientes de receta. | **No hecho / límites:** ver «Inventario (Fase 7), auditoría» en Riesgos: (a) el máximo de 8 líneas y el consumo de accesos de una recepción **no están verificados en Firebase real** (el emulador no aplica el límite de 10/20); (b) el insumo de cada línea se valida al recibir, no al crear (límite de 1000 expresiones por evaluación: con las comprobaciones completas solo cabían 4–5 líneas); (c) sin despliegue ni pruebas físicas; (d) la Fase 8B sigue sin iniciar. | **Ejecutadas:** `flutter analyze lib test` sin errores (solo avisos de estilo ya existentes); Flutter `inventory_test` + `reports_test` (**32 aprobadas**; nuevas: separación de funciones, líneas ilegibles, lectura tolerante, entrada sin motivo, límite de 8 líneas); reglas, suite **completa** con Firestore y Auth (`npm run test:rules`): **456 aprobadas** (`inventario.rules.test.js` 40). **No ejecutadas:** suite completa de Flutter (no se tocó nada transversal), `flutter build`, Firebase real. **Pendiente:** verificaciones del checklist de la Fase 7 (ítems 17–21), despliegue de reglas con su autorización. |
| 8 | **Hecha el 2026-11-19.** *Revisión previa:* `ReportsScreen` era un marcador; el módulo `AppModule.reports` (solo lectura, **solo Admin y Superadmin**) ya existía, así que **no cambió la matriz de permisos ni `firestore.rules`**: los reportes leen con las reglas de Caja, Inventario, Asistencia y Pedidos. Se reutilizaron `Payment`, `Supply`/`Recipe`, `AttendanceRecord`, `staffListProvider`, `attendanceAdminRepositoryProvider` y los componentes de interfaz. *Periodos:* Hoy, 7 días, 30 días y mes actual, siempre por día de Lima (el fin es exclusivo). *Pestañas:* **Ventas** (total, n.º, ticket promedio, hora pico, por método, por día, por cajero), **Platos** (ranking por cantidad con ingreso, costo y margen estimados con la receta y el costo vigente; se calcula solo al pulsar «Analizar» y lee hasta 300 pedidos para cuidar la cuota), **Asistencia** (jornadas y horas por persona, abiertas y regularizadas; en vivo; no calcula pagos ni sanciones), **Inventario y costos** (valor del stock, compras recibidas y mermas del periodo, movimientos por tipo, stock bajo). *Modelos puros* (`report_models.dart`) separados de la lectura (`ReportsRepository`, consultas puntuales por rango de un solo campo, sin índices compuestos). `Purchase` ganó `receivedAt`. *Documentación:* `docs/CHECKLIST_FISICO_FASE_8.md`. | **No hecho:** (a) exportar a CSV/PDF; (b) comparar periodos y gráficos de línea (hay barras de proporción); (c) indicadores de ingresos y reservas en el dashboard (siguen pendientes de la Fase 1); (d) costo y margen **históricos** (se usa el costo vigente de los insumos y la receta de hoy); (e) puntualidad y tardanzas por periodo (el reporte diario de asistencia ya existía en Asistencia); (f) reportes de reservaciones y de cancelaciones; (g) los reportes no están en vivo (salvo Asistencia): se leen al abrir o al pulsar «Actualizar»; (h) un reporte de platos de más de 300 pedidos se trunca y lo avisa; (i) prueba física con datos reales y despliegue de reglas de las fases 6 y 7. | **Ejecutadas:** `flutter analyze` completo: sin incidencias; `reports_test` **12 aprobadas** (periodos incluido el cambio de día en UTC, ventas, platos con y sin receta, asistencia, inventario, permisos, pantalla ancha y angosta y el límite de 300 pedidos); por tocar `Purchase`, `main.dart` y la navegación se repitieron solo `inventory_test`, `login_flow_test` y `permission_service_test` (en total **55 aprobadas** con `reports_test`); reglas: solo el archivo nuevo `reportes.rules.test.js` (**4 aprobadas**: Admin y Superadmin ejecutan las consultas exactas por rango; mesero, cocina y almacén no leen ventas; mesero, cocina y caja no leen compras, movimientos ni asistencia; nadie corrige ventas desde reportes). **No ejecutadas:** `flutter test` y reglas completos (no se tocaron reglas, permisos ni lógica de otras fases), `flutter build`, dispositivos y Firebase real. **Pendiente:** prueba física (checklist) y despliegue de reglas con su autorización. |
| 8B | **Hecha el 2026-11-19; sin desplegar.** *Reglas:* `descuentosInventario/{pedido}` (solo creación), movimientos `consumo` (`validConsumeMovement`), `consumptionDone` en la transición preparando→listo, `canConsume` (Cocina con jornada, Admin, Superadmin) y lectura de `insumos`/`recetas` para Cocina. *App:* `MovementKind.consumo`, `StockMovement.orderId`, `ConsumptionPlanner` (cálculo puro), descuento dentro de `advanceKitchen` y paso de Movimientos con el pedido; `FirestorePaths` con las colecciones de inventario. *Excepción de Admin (mismo día):* `excepcionesInventario`, `forzado` en el marcador, `StockShortage`/`InsufficientStockFailure`, `allowShortage`, `forceReason` en `advanceKitchen` y `ForceReadyDialog`. *Documentación:* este apartado y `docs/CHECKLIST_FISICO_FASE_8B.md`. | **No hecho:** comprobar en reglas que la cantidad coincide con la receta (imposible por el límite de accesos); más de 8 insumos por pedido; devolución automática (descartada); prueba física y despliegue. | **Ejecutadas:** `flutter analyze lib test` sin errores; Flutter `consumption_test` (7), `force_ready_test` (nueva, 11: planificador con faltantes, servicio y diálogo), `kitchen_test`, `inventory_test`, `reports_test` (70 aprobadas); reglas, suite **completa** con Firestore y Auth: **483 aprobadas** (`descuento.rules.test.js` nueva con 27 pruebas, 12 de ellas de la excepción de Admin; las 15 base: descuento atómico, un único descuento, concurrencia, stock negativo, consumo inválido, marcador coherente, tope de 8, permisos de Cocina, sin reposición; `orders.rules.test.js` adaptada para que «listo» incluya el descuento; `inventario.rules.test.js` y `permissions.rules.test.js` ajustadas a la lectura de Cocina). **No ejecutadas:** el flujo real contra Firestore desde la app (la transacción de `advanceKitchen` no tiene prueba automática, solo el planificador y las reglas), suite completa de Flutter, `flutter build`, Firebase real. **Pendientes explícitos (ver «Fase 8B»):** (1) validar la transacción de la app contra Firebase real; (2) probar en Firebase real el límite de 8 insumos y de accesos por lote; (3) las reglas no pueden verificar que cantidades y faltantes coincidan con la receta (auditoría, no control). |
| 9 | **Hecha el 2026-11-27 en local; sin desplegar, sin commit y sin tocar Firebase real.** *Inventarios separados y retiro del rol Almacén* (plan en `docs/PROPUESTA_ASISTENCIA_QR_E_INVENTARIOS.md` §8). **Insumos** (`/app/insumos`: Cocina, Admin, Superadmin) y **Compras** (`/app/compras`: solo Admin/Superadmin, máximo **5 líneas**). Los costos de insumos viven aparte en `costosInsumos/{id}` (solo Admin; Cocina nunca los lee) y la recepción valida el costo de cada línea con un `getAfter` (18 accesos con 5 líneas; ver `docs/LIMITES_FIRESTORE.md`). **Utensilios** (`/app/utensilios`: Mesero, Admin, Superadmin): catálogo solo Admin con auditoría, asignaciones por Mesero, movimientos inmutables y costos versionados en `costosUtensilios` (el Mesero nunca los lee). Almacén se retiró de roles, permisos, navegación, reglas, pruebas y documentación; el historial no se borra. *Pendiente:* `tools/migrate_supply_costs.js` contra Firebase real (requiere autorización), despliegue de reglas y la sonda de límites en un proyecto separado. *Entrega de utensilios:* el Mesero elige a cualquier mesero activo con el directorio mínimo `directorioMeseros` (solo nombre y estado). Checklist: `docs/CHECKLIST_FISICO_INVENTARIOS.md`. |

---

# Guía de Git y GitHub para el equipo

Repositorio: <https://github.com/IsraMagallanes/La-Granja-Azul>

## Reglas de oro

1. **Nadie hace push directo a `main`.** Los cambios llegan a `main` solo mediante **Pull Request (PR)**.
2. **Cada integrante trabaja en su propia rama.** Ejemplos:

| Rama | Para qué |
|---|---|
| `feature/carta` | Módulo de la carta |
| `feature/pedidos` | Módulo de pedidos |
| `feature/inventario` | Módulo de inventario |

3. Antes de crear una rama, actualiza `main`.
4. Antes de abrir un PR, trae a tu rama los últimos cambios de `main`.
5. Haz commits pequeños y con mensajes claros.

> Todos los comandos son para **PowerShell**. Ejecútalos dentro de la carpeta del proyecto, salvo el primero.

## 1. Clonar el proyecto y descargar dependencias

Solo se hace una vez por computadora.

```powershell
cd C:\Users\TU_USUARIO\StudioProjects
git clone https://github.com/IsraMagallanes/La-Granja-Azul.git
cd La-Granja-Azul
flutter pub get
```

Comprueba que el entorno esté sano:

```powershell
flutter doctor -v
```

## 2. Actualizar `main` con `git pull`

Haz esto al comenzar cada día de trabajo y antes de crear una rama nueva.

```powershell
git switch main
git pull origin main
```

## 3. Crear una rama personal desde `main` actualizado

Cada quien usa la rama de su módulo. Ejemplo para la carta:

```powershell
git switch main
git pull origin main
git switch -c feature/carta
```

Para los otros módulos cambia solo el nombre:

```powershell
git switch -c feature/pedidos
git switch -c feature/inventario
```

Comprueba en qué rama estás:

```powershell
git branch --show-current
```

## 4. Guardar cambios con `git add` y `git commit`

```powershell
git status
git add lib/features/carta/carta_page.dart
git commit -m "Agrega pantalla de carta con lista de platos"
```

Para agregar todo lo modificado (revisa antes con `git status` que no haya archivos que no quieras subir):

```powershell
git add .
git commit -m "Agrega pantalla de carta con lista de platos"
```

Recomendaciones para el mensaje:

- Empieza con un verbo: `Agrega`, `Corrige`, `Actualiza`.
- Describe qué hace el cambio, no "cambios" ni "arreglos".

## 5. Subir tu rama

**Primera vez** (la rama aún no existe en GitHub):

```powershell
git push -u origin feature/carta
```

**Siguientes veces** (la rama ya está enlazada):

```powershell
git push
```

## 6. Traer cambios recientes de `main` a tu rama

Hazlo cuando otro compañero ya fusionó su trabajo en `main`, y siempre antes de abrir tu PR.

```powershell
git switch main
git pull origin main
git switch feature/carta
git merge main
```

Si no hay conflictos, sube el resultado:

```powershell
git push
```

## 7. Pull Request: crear, revisar y fusionar

### Crear el PR

1. Sube tu rama (`git push`).
2. Entra a <https://github.com/IsraMagallanes/La-Granja-Azul>.
3. Pulsa **Compare & pull request** (o ve a la pestaña *Pull requests* → **New pull request**).
4. Configura: **base: `main`** ← **compare: `feature/carta`**.
5. Escribe un título claro y una descripción breve de qué cambia y cómo probarlo.
6. Pide la revisión de al menos un compañero en **Reviewers**.

### Revisar el PR

- Abre la pestaña **Files changed** y lee los cambios.
- Comenta líneas concretas si hay dudas.
- Usa **Review changes** → **Approve** o **Request changes**.
- Si piden cambios, haz los commits en tu misma rama y ejecuta `git push`; el PR se actualiza solo.

### Fusionar el PR

- Fusiona solo cuando esté aprobado y GitHub no muestre conflictos.
- Pulsa **Merge pull request** → **Confirm merge**.
- Opcional: pulsa **Delete branch** para borrar la rama en GitHub.

## 8. Actualizar el `main` local después de la fusión

```powershell
git switch main
git pull origin main
```

Si vas a seguir trabajando en el mismo módulo, vuelve a tu rama y trae `main`:

```powershell
git switch feature/carta
git merge main
```

Si ya borraste la rama en GitHub y no la necesitas, bórrala también en tu computadora:

```powershell
git branch -d feature/carta
```

## 9. Cambios locales sin guardar

Si necesitas cambiar de rama o hacer `git pull` y tienes cambios sin commit, puedes guardarlos temporalmente:

```powershell
git stash push -m "trabajo en carta a medias"
git switch main
git pull origin main
git switch feature/carta
git stash pop
```

Alternativa: haz un commit con lo que tengas (`git add .` y `git commit -m "..."`) y cambia de rama después.

Comandos útiles para ver qué tienes:

```powershell
git status
git diff
git stash list
```

## 10. Qué hacer si aparecen conflictos

Un conflicto ocurre cuando dos personas modificaron las mismas líneas. Git lo avisa al hacer `git merge main` o `git pull`.

1. Mira qué archivos tienen conflicto:

   ```powershell
   git status
   ```

2. Abre cada archivo en conflicto. Verás marcas como estas:

   ```text
   <<<<<<< HEAD
   tu versión
   =======
   versión de main
   >>>>>>> main
   ```

3. Deja el código final correcto y **borra las marcas** `<<<<<<<`, `=======` y `>>>>>>>`.
4. Marca el conflicto como resuelto y termina la fusión:

   ```powershell
   git add lib/features/carta/carta_page.dart
   git commit
   ```

5. Comprueba que el proyecto sigue funcionando:

   ```powershell
   flutter pub get
   flutter analyze
   ```

6. Sube el resultado:

   ```powershell
   git push
   ```

Si te enredas y quieres cancelar la fusión antes de terminarla:

```powershell
git merge --abort
```

Si dudas sobre qué versión conservar, pregunta a quien escribió el otro cambio antes de borrar nada.

## 11. Errores comunes

| Mensaje o situación | Causa | Solución |
|---|---|---|
| `error: failed to push some refs ... (non-fast-forward)` | Tu rama remota tiene commits que no tienes | `git pull` y luego `git push` |
| `fatal: The current branch ... has no upstream branch` | Es la primera vez que subes la rama | `git push -u origin nombre-rama` |
| `Your local changes would be overwritten by merge` | Tienes cambios sin guardar | Haz commit o `git stash push` y repite |
| Estoy trabajando en `main` por error (aún sin commit) | No creaste tu rama | `git switch -c feature/carta` (los cambios te acompañan) |
| Hice commit en `main` por error (aún sin push) | Igual que arriba | Crea la rama con `git switch -c feature/carta` y pide ayuda para devolver `main` a su estado |
| `Permission denied` o `Authentication failed` | Falta acceso o sesión de GitHub | Pide que te agreguen como colaborador e inicia sesión de nuevo |
| El PR muestra conflictos | `main` avanzó desde que creaste la rama | Haz el paso 6 y resuelve conflictos (paso 10) |
| La app no compila tras un `pull` | Cambiaron dependencias | `flutter pub get` |

## 12. Recomendaciones para no sobrescribir el trabajo de otros

- **Nunca** uses `git push --force` ni `git push -f`.
- **No** hagas push directo a `main`; usa siempre PR.
- **No** trabajes en la rama de otra persona sin avisarle.
- Ejecuta `git pull origin main` antes de crear una rama y `git merge main` antes de abrir el PR.
- Revisa `git status` antes de cada `git add`.
- Evita editar a la vez los mismos archivos que otro compañero (por ejemplo `pubspec.yaml`, rutas o configuración compartida); avisen por el grupo cuando haya que tocarlos.
- Haz PR pequeños y frecuentes en lugar de uno gigante al final.
- No uses `git reset --hard` ni `git checkout -- .` si no estás seguro: borran cambios sin guardar.
- Para ramas largas, haz `git merge main` seguido para que los conflictos sean pequeños.

---

# Versiones y tecnologías del proyecto

Entorno diagnosticado el **26/10/2026**. Este bloque distingue dos cosas:

- **Requisitos del proyecto:** lo que el proyecto necesita realmente y que todos deben cumplir.
- **Equipo de referencia:** las versiones exactas de la computadora donde se hizo el diagnóstico. Sirven como referencia, no son obligatorias salvo donde se indica.

## Requisitos obligatorios para los compañeros

Estos valores salen de los archivos del proyecto (`pubspec.yaml`, `android/`):

| Requisito | Valor exigido | Origen |
|---|---|---|
| Dart SDK | `^3.13.5` (o superior compatible) | `pubspec.yaml` → `environment.sdk` |
| Flutter | Una versión estable que incluya Dart 3.13.5 o superior (la de referencia es 3.47.7) | Se deriva del requisito de Dart |
| Java del proyecto | Compatibilidad Java 17 | `android/app/build.gradle.kts` |
| Gradle Wrapper | 9.3.1 (se descarga solo con `gradlew`) | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin (plugin Gradle) | 2.4.0 | `android/settings.gradle.kts` |
| Dependencias Dart | Las versiones de `pubspec.lock` (se instalan con `flutter pub get`) | `pubspec.lock` |
| Git | Cualquier versión reciente | — |
| Acceso a Firebase | Proyecto `la-granja-azul-app` | `.firebaserc` |

Para Node.js, npm, Firebase CLI y FlutterFire CLI el proyecto no fija una versión; se recomienda usar versiones actuales y similares a las del equipo de referencia.

## Equipo de referencia (diagnóstico del 26/10/2026)

### Herramientas

| Herramienta | Versión |
|---|---|
| Flutter | 3.47.7 (stable) |
| Dart | 3.13.5 |
| Node.js | 24.21.0 |
| npm | 11.19.0 |
| Firebase CLI | 15.31.0 |
| FlutterFire CLI | 1.4.1 |
| Android Studio | 261.26222.65 |
| Android SDK | 37.0.0 (plataformas 34, 35, 36 y 37.0) |
| Android NDK | 28.2.13676358 |
| Emulador de Android | 37.1.11 |
| JDK Temurin (`JAVA_HOME`) | 21.0.12 |
| JDK de Flutter / Android Studio | 25.0.3 |
| Gradle Wrapper | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Git | 2.55.0.windows.5 |

### Dependencias principales de Flutter

| Paquete | Versión | Uso |
|---|---|---|
| flutter_riverpod | 3.4.3 | Manejo de estado |
| go_router | 18.1.1 | Navegación |
| equatable | 3.0.0 | Comparación de objetos |
| rxdart | 0.28.0 | Programación reactiva |
| firebase_core | 5.1.0 | Base de Firebase |
| firebase_auth | 7.0.1 | Autenticación |
| cloud_firestore | 7.1.0 | Base de datos |
| qr_flutter | 4.1.0 | Generación de códigos QR |
| mobile_scanner | 7.4.2 | Lectura de códigos QR |
| shared_preferences | 2.5.6 | Almacenamiento local |
| url_launcher | 6.3.3 | Abrir enlaces externos |
| flutter_lints (dev) | ^6.0.0 | Reglas de estilo |

## Comandos para consultar las versiones

```powershell
flutter --version
dart --version
node -v
npm -v
firebase --version
dart pub global list
java -version
git --version
flutter doctor -v
```

Para ver la versión de Gradle Wrapper y del plugin de Android:

```powershell
Get-Content android\gradle\wrapper\gradle-wrapper.properties
Get-Content android\settings.gradle.kts
```

Para ver las versiones exactas de las dependencias:

```powershell
flutter pub deps --style=compact
```

> Si `flutterfire --version` no responde, la carpeta `%LOCALAPPDATA%\Pub\Cache\bin` probablemente no está en el `PATH` de Windows. Si `flutter doctor` marca algún problema, compártelo con el equipo antes de continuar.

## Seguridad: qué nunca se sube a GitHub

> ⚠️ **Nunca subas a GitHub claves privadas de Firebase Admin SDK, contraseñas, tokens ni ningún secreto.** Un repositorio, aunque luego se borre el archivo, conserva el historial. Si se sube un secreto por error, avisa de inmediato al responsable del proyecto: hay que **revocar y regenerar** la clave, no solo borrarla.

**No subir:**

- Archivos JSON de cuenta de servicio / clave privada del Firebase Admin SDK (por ejemplo `*-firebase-adminsdk-*.json`).
- Contraseñas, tokens de acceso, claves de API privadas.
- Archivos `.env` o similares con secretos.
- Archivos de firma de Android (`*.jks`, `*.keystore`) ni `key.properties`.

### Diferencia con `google-services.json` y `firebase_options.dart`

| Archivo | Qué contiene | ¿Es un secreto? |
|---|---|---|
| Clave privada de Firebase Admin SDK | Credenciales de administrador con acceso total al proyecto | **Sí. Nunca se sube.** |
| `android/app/google-services.json` | Identificadores de la app Android para conectarse a Firebase | No es una clave privada. Es configuración de cliente. |
| `lib/firebase_options.dart` | Identificadores de las apps (Android, web, Windows) para Firebase | No es una clave privada. Es configuración de cliente. |

`google-services.json` y `firebase_options.dart` los genera FlutterFire y los necesita la app para funcionar; su contenido viaja dentro de la app instalada. Aun así, **la seguridad real está en las reglas de Firestore** (`firestore.rules`) y en la autenticación, no en ocultar estos archivos. Si las reglas son laxas, cualquiera con esos identificadores podría leer o escribir datos.

Antes de cada commit revisa qué vas a subir:

```powershell
git status
git diff --staged
```
