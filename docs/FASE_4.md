# Fase 4: categorías, platos y carta digital

## Cambios y responsabilidades

- `lib/features/menu/models/`: `MenuCategory` y `Dish`, datos y serialización.
- `repositories/`: contrato `MenuRepository` e implementación Firestore. Solo esta implementación consulta Firebase.
- `services/menu_service.dart`: validación compartida entre formularios y escrituras; normalización de textos.
- `controllers/menu_providers.dart`: inyección del repositorio y servicio; combinación de listeners de categorías/platos con Riverpod. Proveedor autoDispose para liberar suscripciones al abandonar las pantallas.
- `widgets/`: formulario de edición, imagen con carga/fallback y estados asíncronos reutilizables.
- `screens/`: administración protegida y carta pública agrupada por categorías, precio en soles y disponibilidad.
- `lib/main.dart`: únicamente registra la implementación del repositorio.
- `lib/core/config/firestore_paths.dart`: nueva colección `categorias`.
- `firestore.rules`: permisos y validación de esquema, tipos, límites y referencia de categoría.
- `test/features/menu_test.dart` y `tools/rules.test.js`: pruebas de fase 4 y seguridad.
- `firebase.test.json` y `tools/package.json`: ejecución aislada de reglas con proyecto demo y puerto 8180; la configuración Firebase de la aplicación permanece intacta.

Se conservan las rutas existentes `/carta` y la ruta administrativa de carta definida en AppRoute, el shell y la matriz de permisos. No se implementan pedidos, carrito, pagos ni fases posteriores.

## Datos y política de desactivación

`categorias/{id}`: `nombre` (string, hasta 120 caracteres), `activo` (bool).
`carta/{id}`: `nombre` (string, 120), `descripcion` (string, 2000), `categoriaId` (ID existente), `precio` (number, > 0 y <= 1000000), `imagenUrl` (HTTPS, hasta 2048 caracteres), `disponible` (bool).

Los textos son obligatorios. Los formularios aceptan coma o punto decimal. Los precios se muestran con dos decimales en soles.

Desactivar una categoría oculta de la carta pública todos sus platos; conserva sus IDs y referencias. La advertencia aparece antes de guardar. Reactivarla vuelve a mostrar sus platos con su disponibilidad individual. Las reglas prohíben eliminar categorías y platos. Se permite editar un plato asociado a una categoría inactiva; sigue oculto hasta reactivarla o trasladarlo a otra categoría. La desactivación es una única escritura: no necesita actualizaciones masivas ni puede dejar referencias huérfanas por carreras entre clientes.

Lectura de ambas colecciones pública, incluyendo documentos de categorías inactivas: desactivar controla presentación, no confidencialidad. No guardar información privada en ellas. Solo perfiles `usuarios/{uid}` activos con rol `admin` o `superadmin` escriben. La ruta y pantalla usan los permisos existentes y Firestore los verifica independientemente.

## Imágenes

No existían carga de archivos, dependencia de Firebase Storage ni reglas de Storage. Se guarda únicamente una URL HTTPS, con vista previa y sustituto visual si no carga. Se requiere alojar imágenes en un servidor accesible públicamente por HTTPS que permita su uso desde la web (cabeceras CORS compatibles con el dominio de la app, sin bloqueo de hotlink). El proveedor y su configuración son responsabilidad del administrador. No hay nueva dependencia, base64, subida de archivos ni cambio de plan Firebase. La validación comprueba el formato de URL; no garantiza que el servidor responda con una imagen.

## Configuración manual de Firebase

1. Revisar las reglas locales y ejecutar las pruebas del emulador antes de publicarlas.
2. Publicar manualmente `firestore.rules` en el proyecto existente cuando se aprueben: `firebase deploy --only firestore:rules`. **No se ha desplegado nada automáticamente.** Sin las nuevas reglas, la app no podrá escribir/leer categorías bajo la política anterior.
3. No se necesitan índices compuestos: las consultas escuchan colecciones completas y ordenan en el cliente; adecuado para una carta de restaurante.
4. No reemplazar `firebase_options.dart`, `firebase.json` ni perfiles existentes. Mantener administrador activo en `usuarios`.
5. Si hay documentos antiguos en `carta` con esquema de prueba (p. ej. solo `nombre`), respaldarlos y migrarlos manualmente al esquema anterior y crear primero sus categorías. El lector usa el esquema de fase 4 y reportará error ante datos incompatibles; no hay migración destructiva automática.

## Ejecución y prueba manual

1. Desde la raíz: `flutter pub get` y `flutter run -d chrome`.
2. Entrar como admin/superadmin y abrir Administración de la carta desde el menú existente.
3. Crear una categoría y editar su nombre. Crear un plato con descripción, categoría, precio `25,50`, URL HTTPS y disponibilidad.
4. Comprobar que campos vacíos, precio 0/negativo/no numérico y URL no HTTPS bloquean Guardar; comprobar vista previa y fallo de imagen.
5. Abrir `/carta` en una ventana privada sin sesión. Debe mostrar categoría, imagen, descripción, `S/ 25.50` y disponibilidad.
6. Mantener ambas ventanas abiertas: editar precio y disponibilidad desde administración y comprobar actualización pública sin recargar.
7. Desactivar una categoría con platos: desaparece el grupo público; los platos permanecen en administración. Reactivarla y comprobar su retorno.
8. Probar sin datos, error de permisos/red y Reintentar. Firestore puede servir caché al perder conexión; la pérdida de red no siempre produce un error inmediato y una escritura puede esperar confirmación.
9. Entrar como mesero/cocina/cajero/almacén: administración denegada. Comprobar además las reglas con el emulador; ocultar botones no sustituye seguridad.

## Pruebas automatizadas

- `flutter analyze`
- `flutter test test/core test/features` (pruebas de autenticación previas y fase 4).
- `flutter test` incluye también el archivo local preexistente `test/widget_test.dart`, que importa `package:aranjazul/main.dart` y espera `MyApp`/contador; no corresponde al proyecto `granja_azul`. Se conserva ese archivo del usuario sin modificar.
- En `tools`: `npm install --no-package-lock` y `npm run test:rules` (Node, Firebase CLI y Java compatible con el emulador). Usa solo emulador local; no ejecuta `verify_live.js` ni toca datos reales.

Las pruebas nuevas cubren validación, serialización, política de categorías, formulario, cambios reactivos de precio/disponibilidad, estados de carga/error/vacío y permisos/esquemas de Firestore.

## Resultados de esta implementación

- `flutter test test/core test/features`: **26 pruebas aprobadas** (incluye regresión de errores de Firestore).
- `npm run test:rules`: **21 pruebas aprobadas**, emulador local con proyecto demo.
- `flutter analyze`: únicamente los tres diagnósticos preexistentes de `test/widget_test.dart` (importación `aranjazul` y clase `MyApp`). Sin diagnósticos en el código de fase 4.
- No se ejecutaron pruebas contra Firebase real ni despliegues. La comprobación con navegador y datos reales queda como prueba manual siguiendo los pasos anteriores.

## Diagnóstico de “No tienes permisos para realizar esta acción”

Origen del texto exacto: `ErrorMapper` traduce `permission-denied`. En fase 4 llegaba desde los listeners de Firestore o desde el guardado; no era el mensaje de la ruta ni del control local de roles. `AuthRedirect` permite `/carta` incluso mientras carga la sesión y sin login. `/app/carta` exige `manageMenu`, asignado solo a admin/superadmin. `SessionResolver` rechaza perfiles inactivos o inexistentes. Ninguno de esos permisos se modificó.

Las dos pantallas consumen el mismo `menuCatalogProvider`: combina `categorias.snapshots()` y `carta.snapshots()` (colecciones completas, ordenadas en el cliente). Si falla cualquiera de las dos, falla la carga de ambas vistas.

Se reprodujo en el emulador con una copia histórica de las reglas anteriores (`tools/fixtures/firestore.pre_phase4.rules`):

| Consulta | Reglas anteriores | Reglas locales fase 4 |
|---|---|---|
| Listar carta sin sesión | Permitida | Permitida |
| Listar categorías sin sesión | Denegada | Permitida |
| Listar ambas como admin/superadmin activo | Categorías denegada | Permitida |
| Crear/editar como admin/superadmin activo | Categorías denegada | Permitida con esquema válido |
| Crear/editar como rol operativo o perfil inactivo | Denegada | Denegada |

No se consultaron las reglas remotas ni el perfil de una sesión real: la reproducción demuestra la incompatibilidad de las reglas anteriores, pero no certifica qué versión está publicada ahora. Si el error ocurre al abrir la carta y siguen publicadas las reglas anteriores, falta publicarlas. Si ocurre solo al guardar, también comprobar rol/activo del perfil real y datos válidos. Ahora el repositorio diferencia lectura y guardado, preserva el código del error e identifica la colección en el mensaje; las pantallas siguen sin consultar Firebase.

### Publicación manual, solo reglas, cuando se decida

Proyecto configurado: **`la-granja-azul-app`**, coincidente en `.firebaserc`, opciones Android/Web de `lib/firebase_options.dart` y `firebase.json`. Base de datos: **`(default)`**.

1. En Firebase Console, seleccionar `la-granja-azul-app` → Firestore Database → base `(default)` → Reglas. Comprobar si aparece el bloque `match /categorias/{category}` y comparar con `firestore.rules` local. Conservar una copia de las reglas publicadas antes de reemplazarlas.
2. Desde la raíz del proyecto, confirmar la cuenta del CLI con `firebase login:list`. Si hace falta autenticarse: `firebase login`. La cuenta debe poder publicar reglas en ese proyecto; no es el rol del usuario dentro de la app.
3. Revisar el archivo `firestore.rules`. El acceso público solo alcanza `carta` y `categorias`; `usuarios` conserva sus restricciones y el resto permanece denegado.
4. Cuando se autorice la publicación, ejecutar exactamente:

   ```powershell
   firebase deploy --only firestore:rules --project la-granja-azul-app
   ```

   Este comando publica el conjunto de reglas Firestore del archivo configurado; no despliega índices, Hosting, Functions, Storage ni modifica perfiles. No se pueden publicar bloques individuales de reglas: se publica el archivo completo, conservando las protecciones del resto de colecciones.
5. Tras propagarse las reglas, usar Reintentar o recargar la app. Probar `/carta` en incógnito sin login y `/app/carta` con un administrador activo. Si el guardado sigue denegado, revisar sin modificar automáticamente `usuarios/{uid}`: `rol` debe ser `admin` o `superadmin`, y `activo` booleano `true`.

No se ha ejecutado ningún despliegue. No se cambiaron roles ni se abrió acceso global a la base de datos.
