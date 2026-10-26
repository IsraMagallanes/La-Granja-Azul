# Estado del proyecto — La Granja Azul

Última actualización: 2026-10-26

## Resumen

| Fase | Estado |
|------|--------|
| 1. Estructura del proyecto | Completada (analyze limpio, 15 pruebas Flutter) |
| 2. Firebase y autenticación | **Completada y verificada contra Firebase real** (Superadmin accedió a su dashboard) |

## Arquitectura

Modular por funcionalidades; presentación (screens/widgets) → controladores
(Riverpod) → servicios/repositorios. Los widgets nunca consultan Firebase: lo
hacen los repositorios, inyectados mediante providers (`authRepositoryProvider`,
`userRepositoryProvider`) y sobrescritos en `main.dart`.

```
lib/
  main.dart, app.dart, firebase_options.dart
  core/
    config/      AppConfig, FirestorePaths
    error/       AppFailure, ErrorMapper
    routing/     AppRoute (catálogo), AuthRedirect (lógica pura), app_router
    shell/       StaffShell (navegación responsiva por rol)
    theme/ validators/ widgets/
  features/
    auth/        modelos de sesión, AuthRepository (+Firebase), controladores, pantallas
    users/       AppUser, UserRepository (+Firestore), StaffProvisioningService (contrato)
    roles/       UserRole, Permission, PermissionService, RoleNavigation
    admin/ waiters/ kitchen/ cashier/ tables/ menu/ orders/ inventory/ reports/
                 pantallas base (placeholders); la lógica no está implementada.
```

### Roles y permisos

`superadmin`, `admin`, `mesero`, `cocina`, `cajero`, `almacen`. La matriz vive
en `PermissionService` y se replica en `firestore.rules`. Superadmin y Admin
comparten el dashboard; solo Superadmin tiene `manageAdmins` y `manageRoles`.

### Sesión y redirección

`sessionProvider` combina `authStateChanges` con un listener del documento
`usuarios/{uid}`, de modo que desactivar un usuario o cambiar su rol surte
efecto en vivo. `AuthRedirect` decide: cargando → `/cargando`; anónimo →
carta (web) o login (móvil); sin perfil o inactivo → `/acceso-denegado`;
autenticado → home de su rol, y bloquea rutas sin permiso.

La web pública es solo la carta (`/carta`): sin login de clientes, carrito,
pedidos ni pagos.

## Firebase

- Proyecto: `la-granja-azul-app` (nombre "La Granja Azul"), cuenta
  horarioapps@gmail.com, plan Spark (sin facturación activada).
- Apps registradas: Android `pe.rgkingenieros.granja_azul`
  (`1:56647616323:android:5dc6069edd9b44dde6d1f6`) y Web
  (`1:56647616323:web:81de814f00013928e6d1f6`). Configuración generada con
  `flutterfire configure` en `lib/firebase_options.dart` (las claves de
  cliente de Firebase no son secretas; la seguridad la dan las reglas).
- Se cambió el `applicationId` de Android de `com.example.granja_azul` a
  `pe.rgkingenieros.granja_azul`.

### Colección `usuarios/{uid}`

| Campo | Tipo | Nota |
|-------|------|------|
| `email` | string | |
| `nombre` | string | |
| `rol` | string | uno de los 6 roles |
| `activo` | bool | |
| `creadoEn` | timestamp | |

Sin contraseñas ni credenciales en Firestore.

### Reglas (`firestore.rules`)

- `usuarios`: lectura del propio perfil (aunque esté inactivo) o por admin/superadmin
  activos; **ninguna escritura desde el cliente** → nadie puede registrarse como
  superadmin ni cambiar su propio rol.
- `carta`: lectura pública; escritura solo admin/superadmin activos.
- Todo lo demás: denegado.

### Primer Superadmin

Script `tools/create_superadmin.js` (Admin SDK), ejecutado desde un equipo de
confianza con una clave de cuenta de servicio guardada **fuera del repo**
(`GOOGLE_APPLICATION_CREDENTIALS`). Pide la contraseña por consola; no se
guarda en ningún lado.

### Altas posteriores de personal

`StaffProvisioningService` define el contrato. Crear cuentas requiere
privilegios de servidor; la opción habitual (Cloud Functions) exige plan
Blaze, **no activado**. Alternativas sin costo: ampliar el script de `tools/`.

## Verificación real (proyecto `la-granja-azul-app`)

- Authentication (correo/contraseña) y Firestore habilitados; reglas publicadas
  con `firebase deploy --only firestore`.
- Conexión con la clave administrativa comprobada (Auth y Firestore) sin
  imprimir su contenido. La clave vive fuera del repo
  (`C:\Users\carlo\firebase-secrets\`) y está cubierta por `.gitignore`.
- Primer Superadmin creado con `tools/create_superadmin.js`: el documento
  `usuarios/{uid}` tiene `rol: superadmin` y `activo: true` (comprobado con
  Admin SDK). El Superadmin inició sesión en la app y accedió a su dashboard
  (confirmado por el usuario).
- `tools/verify_live.js` (12/12 OK): con usuarios temporales (ya eliminados) se
  comprobó login válido/inválido; que un mesero no puede cambiar su rol, crear
  superadmins, leer perfiles ajenos, listar usuarios, editar la carta ni
  acceder a colecciones no declaradas; que sin sesión solo se lee la carta; y
  que un usuario inactivo ve `activo=false`.
- `firebase.json` restaurado con Firestore, emuladores y configuración
  FlutterFire (Android/Web).

## Resultados de pruebas

- `flutter analyze`: sin problemas.
- `flutter test`: 18 pruebas OK (incluye sesión persistida y recuperación de
  contraseña con repositorio simulado).
- `npm run test:rules` (en `tools/`): 13 OK.
- `node verify_live.js` (en `tools/`): 12 OK contra el proyecto real.

## Comandos útiles

- Ejecutar: `flutter run -d chrome`
- Desplegar reglas: `firebase deploy --only firestore`
- Pruebas de reglas: `cd tools && npm run test:rules`
- Nuevo Superadmin: definir `GOOGLE_APPLICATION_CREDENTIALS` con la ruta de la
  clave y ejecutar `node tools/create_superadmin.js`

## Problemas / pendientes

- El envío real del correo de recuperación de contraseña solo se probó con un
  repositorio simulado; probarlo manualmente con un correo real.
- Solo se ha ejecutado en web; comprobar manualmente en Android.
- Alta de personal desde la app: `StaffProvisioningService` es solo un
  contrato. Hacerlo desde servidor con Cloud Functions requiere plan Blaze (no
  activado); alternativa sin costo: ampliar las herramientas de `tools/`.
- Revisar la plantilla del correo de restablecimiento en la consola de Firebase
  (idioma y remitente).
- Recomendado: rotar la clave de servicio si se comparte o se sospecha
  exposición.

## Pendientes de producto

Lógica de pedidos, inventario, reportes, carta digital real, alta de personal
desde la app.
