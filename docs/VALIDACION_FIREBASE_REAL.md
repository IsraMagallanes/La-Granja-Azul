# Validación de `advanceKitchen` contra Firebase real (Fase 8B)

Objetivo: comprobar con el código **real** de la app (`FirestoreOrderRepository.advanceKitchen` y `_deductInventory`) lo que el emulador no mide: los límites de accesos de las reglas en producción (10 por operación, 20 por transacción) para pedidos de 8 insumos, normal y forzado, y el rechazo de 9.

**Estado: preparado, nunca ejecutado.** Nada de lo de abajo se ha corrido todavía.

## Regla de oro

Solo en un **proyecto Firebase de pruebas, aislado** (id con «test» o «prueba»). **Nunca** en `la-granja-azul-app`. El script se niega a correr contra producción, contra un id sin «test»/«prueba» o si `LIVE_CONFIRM` no repite el id. No uses el SDK Admin ni cuentas reales del negocio.

`firebase.json`, `.firebaserc` y `lib/firebase_options.dart` apuntan a producción: por eso **todos** los comandos llevan `--project` explícito y el script recibe su configuración por `--dart-define`, sin tocar esos archivos.

## Autorizaciones necesarias (del propietario)

1. Crear el proyecto de pruebas (por ejemplo `la-granja-azul-test`) con Authentication (correo/contraseña) y Firestore.
2. Desplegar `firestore.rules` **solo** en ese proyecto.
3. Crear las cuentas y los 3 documentos de la sección siguiente.
4. Autorizar la ejecución del script contra ese proyecto.

## Preparación manual (consola del proyecto de pruebas)

Las reglas exigen **correo verificado**, y la consola no permite marcarlo: usa buzones reales (por ejemplo `tucorreo+admin@…` y `tucorreo+cocina@…`) y abre el enlace de verificación que llega.

1. Authentication → crear 2 usuarios: **Admin** y **Cocina**. Verifica ambos correos y anota sus uid.
2. Firestore → crear `usuarios/{uidAdmin}` con `rol: "admin"`, `nombre: "TEST Admin"`, `activo: true` y los demás campos que pida el modelo `AppUser` (ver `lib/features/users/models/app_user.dart`).
3. Firestore → crear `usuarios/{uidCocina}` con `rol: "cocina"`, `nombre: "TEST Cocina"`, `activo: true` (más los campos de `AppUser`).
4. Firestore → crear `estadoAsistencia/{uidCocina}` con `abierta: true` y `asistenciaId: "test"`. Admin está exento de la asistencia.

Todo lo demás (insumos, categoría, platos, recetas, mesas y pedidos) lo siembra el script con los repositorios reales y las reglas.

## Comandos (sin ejecutar)

Desde `Isra`, en la raíz del proyecto. Reemplaza los valores; **no pegues contraseñas en el historial compartido**.

```powershell
# 1. Reglas SOLO al proyecto de pruebas (requiere autorización del propietario)
firebase deploy --only firestore:rules --project la-granja-azul-test

# 2. Datos de la app web del proyecto de pruebas (apiKey, appId, senderId)
firebase apps:sdkconfig WEB --project la-granja-azul-test

# 3. Validación con el código real, en Windows de escritorio
flutter run -d windows -t tool/live_advance_check.dart `
  --dart-define=LIVE_PROJECT_ID=la-granja-azul-test `
  --dart-define=LIVE_CONFIRM=la-granja-azul-test `
  --dart-define=LIVE_API_KEY=<apiKey> `
  --dart-define=LIVE_APP_ID=<appId> `
  --dart-define=LIVE_SENDER_ID=<senderId> `
  --dart-define=LIVE_ADMIN_EMAIL=<correo admin> `
  --dart-define=LIVE_ADMIN_PASSWORD=<clave admin> `
  --dart-define=LIVE_COCINA_EMAIL=<correo cocina> `
  --dart-define=LIVE_COCINA_PASSWORD=<clave cocina>
```

Para repetir en el mismo proyecto añade `--dart-define=LIVE_TABLE_BASE=9200` (cada pedido registrado ocupa una mesa; el script usa una mesa nueva por escenario). El script termina con código 0 si todo coincide con lo esperado, 1 si algo no coincide y 2 si una guarda lo bloqueó.

## Qué prueba cada escenario

| Escenario | Quién | Resultado esperado por diseño |
|---|---|---|
| Barrido de 1 a 8 insumos, normal | Cocina | OK en todos |
| 8 insumos, normal | Admin | OK |
| 9 insumos | Cocina | **La app** rechaza (`AppFailure`), sin escribir nada |
| 8 insumos con faltante: primero sin motivo, luego forzado | Admin | Sin motivo: la app rechaza («stock-insuficiente»). Forzado: OK, con excepción |

El forzado va **al final** porque deja en cero el stock de los insumos 1 a 8.

## Cómo distinguir los dos tipos de rechazo

| | La **aplicación** rechaza | **Firestore** rechaza |
|---|---|---|
| Excepción | `AppFailure` (p. ej. «El pedido usa más de 8 insumos distintos…») | `FirebaseException`, normalmente `permission-denied` |
| Momento | En `ConsumptionPlanner.plan`, tras leer y **antes** de cualquier `tx.set` | Al confirmar la transacción |
| Efecto | No se escribe nada; sin documento en `descuentosInventario` | No se escribe nada; sin documento en `descuentosInventario` |
| Salida del script | `APP rechaza` | `FIRESTORE permission-denied` |

**Un límite de accesos excedido también se informa como `permission-denied`**, igual que una regla incumplida: por el código o el mensaje no se distinguen. Lo que los separa es el patrón entre filas del barrido, donde todo es igual salvo el número de insumos:

- Pasa con n y falla con n+1 con Cocina, y el emulador acepta 8: es el **límite de accesos** (cada insumo suma un acceso a `getAfter` en `consumptionDone`).
- Falla con Cocina pero pasa con Admin con el mismo n: confirma el límite (Admin evita la consulta de jornada, así que le sobra un acceso).
- Falla con todos los n, incluso con 1: no es el límite; revisa permisos, cuentas, `estadoAsistencia`, correo verificado o las reglas desplegadas.
- `aborted` o `failed-precondition`: conflicto de concurrencia, no de reglas.

El script también consulta con Admin, al final, si quedó el marcador `descuentosInventario/{pedido}` (y `excepcionesInventario/{pedido}` en el forzado) para confirmar que un rechazo no dejó escrituras a medias.

## Si falla con 8 insumos

Hay que reducir el máximo: bajar `ConsumptionPlanner.maxSupplies` y los números fijos de `firestore.rules` (los `getAfter` de `consumptionDone`, `d.linea < 8`, `insumos <= 8` y el límite de 8 faltantes). No lo cambies sin revisar `descuento.rules.test.js`. Esa corrección es un cambio de código aparte, con su propia autorización.

## Qué NO valida

- La interfaz (`KitchenScreen`, el diálogo «Falta stock», el flujo mesero → cocina): solo con una compilación de la app apuntando al proyecto de pruebas, con otro `firebase_options` y otro punto de entrada.
- Las reglas de las demás fases, que siguen cubiertas por las pruebas del emulador (`tools/*.rules.test.js`).
- El tope de 20 por transacción con más de 8 insumos: la app no lo permite (máximo 8).
- La concurrencia de dos cocineros a la vez (paso 3 del checklist): se prueba a mano con dos dispositivos.
- Windows de escritorio es el destino previsto: requiere las herramientas de compilación de C++ para Windows. No se probó que el punto de entrada compile.

## Limpieza

Sin SDK Admin no se puede borrar: las reglas prohíben borrar pedidos, movimientos y marcadores. La limpieza es **eliminar el proyecto de pruebas completo** desde la consola de Firebase (o desactivarlo). Por eso nunca debe usarse un proyecto con datos reales.
