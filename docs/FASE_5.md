# Fase 5 — Mesas y pedidos de meseros

## Base revisada y alcance

Trabajo realizado en **`cristi`**, inicialmente limpia, sobre `9986465` (`Integra fase 4 conservando fases anteriores`), que contiene la integración de las fases 1–4: autenticación y verificación de correo, roles, personal, asistencia QR y carta digital. Se conservaron las rutas y los módulos anteriores. No se cambiaron opciones Firebase, configuración de plataformas, dependencias, datos reales ni roles de cuentas. No se hizo push, merge ni despliegue.

Se implementan mesas, apertura y edición de pedidos y su registro. No hay cocina operativa, pagos, cierre de caja, inventario ni liberación por pago.

## Responsabilidades y archivos

- `features/tables/models/restaurant_table.dart`: mesa y ocupación derivada del vínculo al pedido activo.
- `features/tables/repositories/{table_repository,firestore_table_repository}.dart`: contrato, listeners y creación/edición transaccional de mesas.
- `features/tables/services/table_service.dart`: validación de número y capacidad.
- `features/tables/controllers/table_providers.dart`: inyección y estado reactivo.
- `features/tables/screens/tables_screen.dart` y `widgets/table_editor.dart`: listado, apertura de pedido, formulario y controles por rol.
- `features/orders/models/{restaurant_order,order_item}.dart`: estados, detalle histórico, subtotales y total en centavos.
- `features/orders/repositories/{order_repository,firestore_order_repository}.dart`: listeners y transacciones de apertura, detalles y transiciones.
- `features/orders/services/{order_service,order_policy}.dart`: validaciones de cantidades/observaciones y política de edición.
- `features/orders/controllers/order_providers.dart`: estado y filtro de pedidos propios según sesión.
- `features/orders/screens/orders_screen.dart`: listado de pedidos persistidos.
- `features/orders/widgets/{order_detail,item_editor,operation_button,order_async_view}.dart`: detalle, formulario, acciones con estado de guardado y carga/error/reintento.
- `features/waiters/screens/waiter_screen.dart`: pestañas Mesas y Mis pedidos.
- `main.dart`: solo inyección de los dos repositorios Firebase nuevos.
- `core/config/firestore_paths.dart`: nombres `mesas` y `pedidos`.
- `features/roles/models/permission.dart` y `services/permission_service.dart`: permiso `manageTables`, toma de pedidos para administradores y consulta de pedidos propios para meseros.
- `firestore.rules`: bloques específicos de mesas/pedidos/detalles; conserva todas las reglas anteriores.
- `test/features/orders_test.dart`, `test/support/order_fakes.dart`: dominio, servicios, política, estado y widgets con repositorios falsos.
- `test/features/login_flow_test.dart`: se conserva la prueba de entrada del mesero, actualizando la expectativa del placeholder al módulo real e inyectando repositorios falsos. Ninguna prueba se desactiva.
- `tools/orders.rules.test.js`: pruebas de reglas, transacciones concurrentes y persistencia/listeners.
- `tools/support.js`: permite a las pruebas anteriores tomar el host/puerto y proyecto demo del entorno del emulador; no cambia la configuración de la app.

Las interfaces no consultan Firebase. Los modelos no dependen del SDK. Las escrituras sensibles se resuelven en repositorios transaccionales y se vuelven a verificar en reglas, incluso si un cliente omite el servicio o los botones.

## Permisos

Se conserva el requisito de fase 3: perfil activo **y correo verificado**.

| Rol | Mesas | Pedidos |
|---|---|---|
| Mesero | Consultar ocupación, abrir sobre mesa activa libre | Consultar y editar solo propios mientras estén abiertos; registrar o cancelar |
| Admin / Superadmin | Crear, editar capacidad, activar/desactivar; abrir pedidos | Consultar todos; gestionar cualquier pedido abierto; responsable original inmutable |
| Cajero | Consultar | Consulta de pedidos y detalles; sin escritura |
| Cocina | Sin gestión de mesas | Consulta de pedidos y detalles; sin escritura |
| Almacén | Sin acceso | Sin acceso |
| Anónimo / perfil inactivo / correo no verificado | Sin acceso | Sin acceso |

La carta `/carta` continúa pública. Los permisos del resto de módulos permanecen intactos. No se reasignan responsables ni roles automáticamente.

Rutas: `/app/mesas`, `/app/pedidos` y módulo `/app/mesero` con pestañas. La pantalla inicial de cada rol no cambia. El mesero consulta pedidos con `where('meseroId', isEqualTo: uid)`: las reglas rechazan una consulta global de ese rol. Admin/superadmin/cocina/caja consultan todos según su permiso previo de consulta.

## Datos y validaciones

### `mesas/{numero}`

- `numero`: string canónico entre `1` y `9999`, igual al ID; no admite ceros iniciales ni duplicados con otros IDs.
- `capacidad`: entero de 1 a 50.
- `activo`: booleano.
- `pedidoActivo`: ID de pedido o null.

El número es identidad estable y no se renumera al editar: se editan capacidad y activación. No se eliminan mesas. La creación transaccional rechaza un número existente. Para otro número se crea otra mesa y, estando libre, se desactiva la anterior, conservando el historial.

Una mesa está ocupada si tiene pedido abierto o registrado vinculado. El vínculo se conserva atómicamente con el pedido y no puede editarse de forma aislada. No se permite desactivar una mesa con pedido activo, ni desde la interfaz ni con una escritura directa.

### `pedidos/{id}`

`mesaId`, `meseroId` (UID del actor que abre), `meseroNombre` (nombre copiado del perfil y validado por reglas), `creadoEn`, `actualizadoEn` (hora del servidor), `estado`, `revision` (entero), `cantidadDetalles` y `detalleModificado` (ID del plato de la última mutación).

Mesa, responsable, nombre histórico del responsable y fecha de creación son inmutables. El nombre se muestra en la interfaz; el UID se conserva para autorización. Fechas mostradas en hora de Lima mediante la utilidad existente `LimaTime`. `revision` aumenta de uno en uno. `cantidadDetalles` cuenta platos diferentes, no unidades; máximo 50 platos por pedido.

### `pedidos/{id}/detalles/{platoId}`

`nombre`, `precio` (copias de la carta al agregar), `cantidad` (entero 1–99), `observaciones` (opcional, representada por string vacío, hasta 500 caracteres).

El repositorio lee plato y categoría dentro de la transacción y toma el precio del servidor, nunca del formulario. Las reglas exigen plato disponible y categoría activa al agregar, y nombre/precio exactamente iguales a la carta. Después solo permiten cambiar cantidad y observaciones, o retirar el detalle mientras el pedido sea abierto. El mismo plato tiene un único detalle; para más unidades se edita su cantidad.

Cambiar precio, nombre, disponibilidad o categoría de la carta no altera detalles anteriores. Se puede seguir editando un detalle existente con su precio histórico aunque el plato se haya deshabilitado; no se puede agregar como nuevo. Retirarlo y agregarlo de nuevo aplica el precio vigente y vuelve a validar disponibilidad.

Subtotales y total no se almacenan como campos independientes manipulables: se calculan desde los detalles persistidos. Cada precio unitario se redondea al centavo, se multiplica por cantidad y se suman enteros, evitando acumulación de errores binarios. Se muestran en soles con dos decimales.

## Estados mínimos y fases posteriores

| Origen | Destino | Efecto |
|---|---|---|
| Nueva apertura | `abierto` | Bloquea mesa; editable; puede estar vacío |
| `abierto` | `registrado` | Requiere al menos un detalle; bloquea edición y mantiene mesa ocupada |
| `abierto` | `cancelado` | Libera mesa en la misma transacción; conserva pedido y detalles históricos |

`registrado` y `cancelado` son inmutables en esta fase. No se puede reabrir, reasignar, borrar ni inventar estados como pagado/preparado. **Un pedido registrado mantiene la mesa ocupada y no se puede cerrar o cancelar desde fase 5.** Usar pedidos abiertos/cancelados para pruebas repetibles. Antes de registrar, la interfaz pide confirmación.

La fase de cocina podrá consumir pedidos registrados y añadir sus transiciones explícitas. Una futura fase de cobro/cierre deberá liberar la mesa de forma atómica con su estado terminal, validando el vínculo exacto y sus permisos. Estas acciones y reglas no se han anticipado.

## Integridad y concurrencia

- Apertura: transacción lee la mesa, comprueba activa/libre y crea pedido + vínculo. Dos meseros compiten por el mismo documento; uno confirma y el otro reintenta y encuentra ocupación. Las reglas también impiden pedidos sin vínculo y reemplazar un vínculo existente.
- Desactivación: transacción sobre la misma mesa. Si una apertura gana, no se desactiva; si gana la desactivación, no se abre el pedido.
- Mutación de detalle: transacción lee pedido y detalle, aplica cambio y aumenta revisión/contador del padre. Las reglas exigen la misma revisión y el mismo ID de detalle, y verifican el contador con la existencia antes/después. No puede falsificarse el contador para registrar pedidos vacíos o escribir detalles sin actualizar el padre.
- Registro/cancelación: transacción valida estado abierto y vínculo a mesa. Las reglas impiden cambios después del registro, incluso cuando compiten con otra edición. Cancelar requiere liberar exactamente la mesa de ese pedido en la misma operación.
- Ediciones concurrentes se serializan por revisión del padre. Si dos usuarios guardan cantidades distintas del mismo producto, prevalece el último guardado válido; son cantidades absolutas, no incrementos acumulativos. Una acción que encuentre el pedido ya registrado/cancelado se rechaza.
- Las transacciones requieren conexión. Los listeners pueden mostrar caché; no se confirma una apertura o edición offline como si hubiera sido aceptada por servidor. Los datos confirmados se recuperan tras reiniciar la app.

## Pruebas automatizadas

Resultados: `flutter analyze --no-pub` sin incidencias; `flutter test` **175 aprobadas** (incluye fases anteriores y 7 nuevas de fase 5); suite Node completa **107 aprobadas**, incluidas **15 nuevas** de pedidos y concurrencia.

Comandos desde la raíz:

```powershell
flutter analyze
flutter test
```

Para ejecutar toda la suite de reglas/herramientas de forma aislada usando la configuración de pruebas existente, desde `tools` (dependencias declaradas, Java y Firebase CLI disponibles):

```powershell
firebase emulators:exec --config ../firebase.test.json --only firestore --project demo-la-granja-azul "node --test --test-concurrency=1"
```

Solo pedidos:

```powershell
firebase emulators:exec --config ../firebase.test.json --only firestore --project demo-la-granja-azul "node --test orders.rules.test.js"
```

Las pruebas crean perfiles, mesas y pedidos **solo dentro del emulador demo**; no usan cuentas reales ni Admin SDK contra producción. Si el puerto de pruebas 8180 está ocupado, usar una copia temporal local de `firebase.test.json` con otro puerto libre. En esta implementación se usó 8380 para no interferir con otros emuladores. Se adaptó el helper de pruebas previas para usar `FIRESTORE_EMULATOR_HOST` y `GCLOUD_PROJECT` suministrados por el CLI.

Cobertura: roles, correo verificado/inactividad, restricciones de consulta, datos inválidos, copia histórica de precio/nombre, mutaciones sin revisión, suplantación, transiciones ilegales, apertura simultánea, desactivación concurrente, lectura desde otro cliente y notificaciones en vivo. Se conservaron todas las pruebas anteriores; los primeros fallos de la nueva suite se corrigieron antes del resultado final.

## Prueba manual con administrador y mesero

No se realizaron pruebas con datos reales. Los pasos siguientes son una comprobación manual pendiente tras autorizar la publicación de reglas en el entorno elegido.

1. Desde la raíz, `flutter pub get` y `flutter run -d chrome`. Usar cuentas existentes con perfil activo y correo verificado; no cambiar roles para la prueba.
2. Administrador: abrir **Mesas** (`/app/mesas`), crear mesa 1 con capacidad 4. Intentar crear otra mesa 1 y probar capacidad 0: debe rechazarse. Editar capacidad a 6. Desactivar y reactivar estando libre.
3. Administrador: en Carta confirmar una categoría activa con un plato disponible y precio conocido (por ejemplo S/ 25.50).
4. Mesero: iniciar sesión en otra ventana. En **Mesero → Mesas**, abrir pedido en mesa 1. Debe pasar a Ocupada también en la ventana administrativa.
5. Añadir 2 unidades del plato con observación. Debe mostrar subtotal/total S/ 51.00. Editar cantidad y observación; retirar un producto y volver a agregarlo. Cantidad cero, decimal, negativa o mayor que 99 debe rechazarse.
6. Administrador: consultar **Pedidos** (`/app/pedidos`); puede editar ese pedido abierto conservando el mesero responsable. Intentar desactivar la mesa ocupada: debe impedirlo.
7. Cambiar en Carta el nombre/precio del plato ya agregado. El detalle existente debe conservar nombre y precio anteriores. Deshabilitar otro plato o categoría: no debe poder seleccionarse para agregar.
8. Recargar la ventana del mesero: deben recuperarse el pedido y sus detalles. Cancelar el pedido abierto: la mesa debe quedar Libre y el pedido Cancelado permanecer en el historial sin controles de edición.
9. Con dos meseros existentes en ventanas separadas, intentar abrir al mismo tiempo la misma mesa libre. Solo uno obtiene pedido. El otro ve la mesa ocupada o un error comprensible; cada mesero solo ve sus propios pedidos.
10. Abrir otro pedido y añadir un plato. Pulsar **Registrar pedido** y confirmar. Ya no debe admitir edición ni cancelación y la mesa seguirá ocupada hasta una fase posterior de cierre. Cocina/caja pueden consultar desde su ruta existente de Pedidos; no tienen controles de mutación. No hay flujo de cocina ni cobro.
11. Sin sesión, `/carta` sigue disponible; mesas y pedidos no son públicos. Probar listas vacías y errores de red/permisos con Reintentar. El total se muestra al abrir el detalle; el listado muestra cantidad de productos y responsable.

## Configuración y despliegue pendientes

- Proyecto existente: **`la-granja-azul-app`**, base **`(default)`**. No se modificó `firebase.json`, `firebase_options.dart`, `.firebaserc` ni `firestore.indexes.json`.
- Pendiente revisar/publicar manualmente **el archivo completo `firestore.rules`**, que ahora incluye mesas y pedidos y conserva fases 1–4. Hasta publicarlo, producción puede devolver `permission-denied` al consultar las colecciones nuevas.
- Cuando se autorice explícitamente, desde la raíz: `firebase deploy --only firestore:rules --project la-granja-azul-app`. Ese comando no se ejecutó.
- **Sin índices compuestos nuevos**. El filtro por `pedidos.meseroId` usa el índice simple automático de Firestore; conservarlo habilitado. Ordenación local, sin consultas de collectionGroup. No hay índices que desplegar en esta fase.
- Sin Storage, Functions, servicios externos, nuevas dependencias ni cambios de plan. No se crearon colecciones ni datos reales desde esta sesión: se crearán con las primeras operaciones autorizadas desde la app tras publicar reglas.
