# Estado del proyecto — La Granja Azul

Última actualización: 2026-10-26 (Fase 3)

## Resumen

| Fase | Estado |
|------|--------|
| 1. Estructura del proyecto | Completada (analyze limpio, 15 pruebas Flutter) |
| 2. Firebase y autenticación | **Completada y verificada contra Firebase real** (Superadmin accedió a su dashboard) |
| 3. Personal y asistencia QR | **Implementada y probada en local** (analyze limpio, 142 pruebas Flutter, 77 de reglas con emulador). **Pendiente de desplegar y de probar con Firebase real y un Android físico** (ver "Fase 3") |

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
- `flutter test`: **142 pruebas OK** (18 de Fases 1–2 + validaciones DNI/CE/
  celular, jerarquía de roles, bajas y modal, restricciones, lista/paginación,
  QR, terminal, asistencias, horarios, dashboard y regularización).
- `npm run test:rules` (en `tools/`): **77 OK** con el emulador (13 de Fase 2 +
  64 de Fase 3: altas, duplicados, formatos, escalamiento, bajas, motivos
  confidenciales, restricciones, auditoría, QR, terminales, entradas/salidas,
  regularización, horarios y correcciones).
- `flutter build apk --debug`: compila.
- `node verify_live.js` (en `tools/`): 12 OK contra el proyecto real.

## Fase 3: gestión de personal y asistencia QR

### Decisión de arquitectura: reglas de Firestore como "API segura"

El proyecto está en plan **Spark** (sin Cloud Functions, que exigen Blaze, no
activado). No hay servidor propio, así que la validación del servidor se hace
con **`firestore.rules`**, que Firebase ejecuta del lado del servidor aunque el
cliente sea modificado:

- La hora de cada marcación es `request.time` (hora del servidor): el cliente
  no puede enviar otra (probado).
- Un lote atómico (`WriteBatch`) consume el token QR, crea/cierra la asistencia
  y actualiza el estado de jornada; si cualquier regla falla no se escribe nada.
- Ninguna credencial administrativa vive en Flutter. Las claves de servicio solo
  se usan en `tools/`.

Limitaciones que esto implica (no se simulan; requieren Blaze/servidor):

- No hay limitación de frecuencia (rate limiting): un trabajador autenticado
  podría crear muchos tokens QR. Recomendado: Firebase App Check y/o Cloud
  Functions al activar Blaze.
- La creación de cuentas de Auth (personal y terminales) usa una **instancia
  secundaria de Firebase Auth en el cliente** (contraseña aleatoria que nadie
  conoce + correo de restablecimiento; en terminales, contraseña fijada por el
  Superadmin y no almacenada). Como el registro por correo está habilitado en
  Firebase, cualquiera puede crear una cuenta de Auth, pero sin perfil en
  `usuarios/` solo ve "acceso denegado". Más seguro con Cloud Functions +
  Admin SDK.
- No hay "cron" servidor: tardanzas/ausencias se calculan al consultar el
  dashboard (hora de Lima); no se generan avisos ni sanciones automáticas.

### Endurecimiento previo al despliegue

- **Cuentas huérfanas:** el alta crea la cuenta de Auth, guarda la ficha en un
  lote atómico y, si ese lote falla, elimina la cuenta recién creada
  (`PendingAccount.rollback`). Lo mismo al autorizar una terminal. El correo de
  contraseña se envía solo después de guardar la ficha.
- **Contraseña inicial:** 32 caracteres aleatorios (`Random.secure`) que nadie
  conoce ni se guardan; el trabajador la define con el enlace oficial de
  restablecimiento de Firebase. Si el envío falla, el alta lo avisa y la ficha
  tiene "Reenviar enlace de contraseña". Plantilla y política de contraseñas
  viven en la consola de Auth (no se tocaron).
- **Personal ≠ terminal:** `isTerminal()` exige que la cuenta NO tenga perfil en
  `usuarios`; no se puede registrar como terminal una cuenta de personal ni
  crear un perfil de personal sobre una terminal (con pruebas).
- **Credenciales copiadas:** la tablet genera un secreto aleatorio en su
  almacenamiento local y lo registra una sola vez en `terminalClaves/{uid}`
  (ilegible desde cualquier cliente, sin actualización). Cada marcación escribe
  `terminalPruebas/{uid}` con ese secreto y las reglas lo comparan; el token QR
  no se consume sin esa prueba. Un segundo equipo con el mismo correo/contraseña
  no puede enlazarse ni marcar. El Superadmin restablece el enlace desde
  `/app/terminales` (cambio de tablet o sospecha de copia). Límite: el primer
  equipo en iniciar sesión tras autorizar la terminal se enlaza; hacerlo en el
  momento y desde la tablet real. No sustituye a App Check (Play Integrity).
- **Auditoría de restablecimientos:** se registra, pero las reglas no pueden
  exigirla en un borrado.
- Reglas validadas contra el proyecto real con
  `firebase deploy --only firestore --dry-run` (compila; sin desplegar).

### Activación de trabajadores (correo + WhatsApp)

Flujo:

1. El administrador registra al trabajador. Se crea su cuenta en Authentication
   con **contraseña aleatoria** (32 caracteres, `Random.secure`) que nadie
   conoce. La sesión del administrador no se toca (instancia secundaria de Auth).
2. Tras guardar la ficha se envían **dos correos oficiales de Firebase**: el
   enlace para **definir la contraseña** (el mismo mecanismo de recuperación de
   contraseña) y el de **verificación del correo**. Si falla la ficha, la cuenta
   se elimina (sin huérfanas). Si falla un envío, la ficha queda y el diálogo de
   alta lo indica (cada correo es independiente).
3. Botón **«Enviar bienvenida por WhatsApp»** (diálogo de alta y ficha del
   trabajador): abre `https://wa.me/51<celular>?text=…` con `url_launcher`; el
   administrador pulsa enviar. El mensaje solo dice que revise sus dos correos;
   **no lleva contraseña ni enlaces de activación**. Sin WhatsApp Business ni
   APIs de pago.
4. **«Pendiente de activación»** (lista y ficha) hasta que `usuarios/{uid}.activadoEn`
   existe. Ese campo lo escribe la propia app la **primera vez que el trabajador
   entra con `emailVerified = true`** (las reglas solo lo permiten una vez, con
   hora del servidor, token verificado y perfil activo). Haber enviado el correo
   no activa la cuenta.
5. **Acceso**: dashboard solo con perfil `activo = true` **y** correo verificado.
   Sin verificar se muestra `/verificar-correo` (reenviar verificación, reenviar
   enlace de contraseña, «Ya verifiqué», cerrar sesión). Además las reglas exigen
   `request.auth.token.email_verified` para cualquier dato (solo se puede leer
   el propio perfil para mostrar esa pantalla). Las terminales (cuentas de
   dispositivo) no requieren correo verificado.
6. Después de activada, el trabajador entra con correo y contraseña; no se pide
   otro cambio. El administrador puede **reenviar el enlace de contraseña**
   desde la ficha. Reenviar la *verificación* solo es posible desde la sesión del
   propio trabajador (Firebase lo exige): lo hace en la pantalla de verificación.
7. Duplicados: se comprueba antes (índices de documento y correo, incluso de
   bajas) y Auth rechaza correos repetidos (mensaje claro).

**Correos y diálogo de alta (corrección tras prueba real):**
- Diagnóstico: `sendOobCode` (REST de `sendPasswordResetEmail`) respondió 200 en
  ~0.5–0.8 s desde el equipo de desarrollo; la protección de enumeración de
  correos está activa (`enableImprovedEmailPrivacy: true`), por lo que Firebase
  responde igual exista o no la cuenta: «enviado» solo puede significar
  «solicitud aceptada», nunca «entregado». La lentitud observada es de red del
  dispositivo y la app no tenía tiempo máximo ni indicador, así que el alta
  quedaba esperando sin mostrar el diálogo de WhatsApp.
- `core/async/request_guard.dart`: tiempo máximo (20 s), una solicitud por clave
  y pausa de 60 s tras un éxito; fallo o tiempo agotado permiten reintentar ya.
- `auth/services/email_requester.dart`: contraseña y verificación con mensajes
  que no afirman más de lo confirmado. Lo usan «¿Olvidaste tu contraseña?», la
  pantalla de verificación y «Reenviar enlace» de la ficha.
- Alta: diálogo de progreso (`core/widgets/progress_dialog.dart`); los dos
  correos salen en paralelo con tope de 20 s cada uno. El diálogo final
  («Enviar bienvenida por WhatsApp» y «Finalizar», no se cierra tocando fuera)
  indica qué correo no se confirmó y permite «Reintentar envío» sin crear otra
  cuenta. El botón de WhatsApp sigue también en la ficha.
- `node tools/check_staff_accounts.js` (solo lectura): compara Authentication y
  Firestore (huérfanas, perfiles sin cuenta, correos/documentos, verificación y
  activación) sin mostrar contraseñas ni enlaces.
- Límites de Firebase (Spark): cuota diaria de correos y `too-many-requests`;
  se muestran con mensaje claro.

**Cambio de correo del Superadmin (el actual es ficticio):**
`node tools/change_superadmin_email.js` (simulación) y `--apply`. Pide el nuevo
correo por consola (dos veces), comprueba que no pertenezca a otra cuenta
(Authentication, `usuarios`, índice `correos`), actualiza Authentication
(`emailVerified: false`, misma contraseña/UID) y luego `usuarios/{uid}` +
auditoría + índice de correos en un lote atómico. Si Firestore falla, revierte
Authentication; si tampoco puede, repetir con el mismo correo reanuda lo
pendiente. La lógica pura está en `tools/lib/email_change.js` (pruebas en
`tools/email_change.test.js`). No crea ni borra cuentas. Después: entrar a la
app con el correo nuevo y la misma contraseña, «Reenviar verificación» desde la
pantalla de verificación, abrir el enlace en ese buzón y comprobar con
`node tools/check_superadmin_auth.js` antes de publicar las reglas restrictivas.

**Orden seguro de publicación:** (0) cambiar el correo ficticio por uno real; (1) el Superadmin entra con la app nueva y
verifica su correo con el enlace real de Firebase; (2) `node tools/check_superadmin_auth.js`
(solo lectura) debe decir «Seguro endurecer»; (3) `node tools/complete_superadmin.js --interactive`
(simulación) y luego con `--apply`; (4) `firebase deploy --only firestore`.
Nota: en producción ya hay reglas de Fase 3 publicadas **sin** `email_verified`
(529 líneas); las locales (541) añaden verificación de correo y activación.

**Atención (Superadmin existente):** su correo en Authentication figura
`emailVerified: false`. Al desplegar las reglas nuevas, entrará a la pantalla de
verificación y deberá abrir el enlace que le llegue. Si no puede,
`tools/complete_superadmin.js --verify-email --apply` marca solo ese campo.

### Error «Sin conexión» al iniciar sesión en Android

Se reprodujo una vez en el equipo físico conectado (Android 16, HyperOS): el
primer inicio tras instalar devolvió `network-request-failed` aunque el DNS
resolvía; el segundo intento llegó a Firebase (respondió credencial inválida,
no un fallo de red) y no volvió a ocurrir. Revisado: `google-services.json`,
`applicationId` y `appId` coinciden; `INTERNET` está en el manifiesto
principal (release incluido; antes solo estaba en debug). Medidas: reintento
automático único del inicio de sesión ante `network-request-failed`; en depuración
se imprime la excepción real (`Auth error: tipo -> detalle`) para distinguir las
causas. Si persiste en otro equipo, revisar: restricciones de la clave de API de
Android (huella SHA-1/paquete) en Google Cloud, permiso de datos/Internet por app
de MIUI/HyperOS, y fecha/hora del dispositivo.

### Gestión de personal (`features/staff`, pantalla `/app/usuarios`)

- Colección `usuarios/{uid}` ampliada: nombres, apellidos, tipo y número de
  documento (DNI 8 dígitos / CE 9–12 alfanuméricos), correo, celular (9 dígitos,
  +51), celular alternativo opcional, rol, `estado` (activo / suspendido /
  baja), `activo` (derivado: bloquea el acceso), fecha de ingreso, horario.
- Duplicados: índices `documentos/{numero}` y `correos/{email}` creados en el
  mismo lote que el alta y **nunca borrados**, por lo que también detectan a
  personal dado de baja. Documento y correo son inmutables.
- Lista responsiva: búsqueda (nombre, documento, correo, sin tildes), filtros
  por rol y estado, paginación de 20. En la lista el documento y el celular van
  enmascarados; la ficha completa solo la ven admin/superadmin.
- Jerarquía (UI, `StaffPolicy` y reglas): Superadmin asigna admin + roles
  operativos; Admin solo mesero/cocina/cajero/almacén; nadie crea superadmins
  desde la app; nadie se administra a sí mismo; un Admin nunca toca a otro Admin.
- Bajas: modal obligatorio (Renuncia / Despido / Suspensión / Otro, motivo
  escrito ≥ 10 caracteres y casilla de confirmación). Baja lógica: `activo=false`
  bloquea el acceso en vivo (la sesión ya escucha el perfil); cuenta e historial
  se conservan. Reactivar también exige motivo.
- Motivos confidenciales en `movimientosPersonal/` (solo lee el Superadmin).
  `usuarios` solo guarda el *tipo* de la última baja.
- Restricciones de recontratación (`restricciones/{documento}`, pantalla
  `/app/restricciones`): solo Superadmin; justificación confidencial en
  `restricciones/{doc}/privado/detalle`, fecha de revisión obligatoria (se marca
  "revisión pendiente" al vencer). **Informativas**: al crear un trabajador con
  documento restringido solo se muestra un aviso, nunca se bloquea.
- Auditoría (`auditoria/`, pantalla `/app/auditoria`, solo Superadmin): quién,
  cuándo, acción, objetivo y nombres de campos cambiados (sin valores ni
  motivos). Las reglas exigen que cada escritura administrativa incluya su
  registro de auditoría en el mismo lote y a nombre de quien escribe; es
  append-only.

### Asistencia por QR (`features/attendance`)

Flujo:

1. **Trabajador** (`/app/mi-asistencia`, todos los roles): "Generar QR de entrada /
   salida" crea `qrTokens/{id}` (id aleatorio de 128 bits). El QR contiene solo
   `GA1:<id>`, sin datos personales. Vigencia 45 s (contador en pantalla), un
   solo uso. **Generar el QR no registra asistencia.** Ve su historial, turno y
   puede enviar solicitudes de corrección.
2. **Terminal Android** (`/asistencia/terminal`, `mobile_scanner`, una cámara):
   cuenta de dispositivo autorizada en `terminales/{uid}`. Escanea, identifica
   entrada/salida por el token y registra solo tras pasar las reglas. Muestra
   confirmación (nombre de pila + hora del servidor, Lima) o el motivo del rechazo.
3. **Servidor (reglas)**: terminal activa; trabajador activo; token sin usar y de
   ≤ 45 s; tipo coherente (entrada ↔ sin jornada abierta; salida ↔ jornada
   abierta del mismo registro); `entrada`/`salida` = `request.time`. Impide
   entradas duplicadas, salidas sin entrada y reutilización de QR.
4. El personal en su teléfono **no puede** marcar: `asistencias` y
   `estadoAsistencia` solo se escriben desde terminales o por regularización
   autorizada; el router solo deja a la terminal en `/asistencia/terminal` y
   redirige al personal fuera de esa ruta.
5. **Terminales** (`/app/terminales`, Superadmin): alta (crea la cuenta del
   dispositivo con contraseña definida por el Superadmin), revocar y reactivar;
   la revocación es efectiva en vivo (la sesión escucha `terminales/{uid}`).

Administración (`/app/asistencia`, admin/superadmin):

- **Hoy**: presentes, puntuales, tardanzas (minutos) y ausencias, según el
  horario asignado y la hora de Lima (turnos nocturnos incluidos).
- **Historial** con filtros (rango, trabajador, tardanzas, regularizadas,
  abiertas).
- **Horarios**: hora de inicio/fin, tolerancia (0–120 min), días y turno
  nocturno (fin ≤ inicio). Se asignan desde la ficha del trabajador.
- **Regularización**: solo Superadmin o Admin autorizado por el Superadmin
  (`puedeRegularizar`); motivo obligatorio, auditoría, nunca sobre uno mismo ni
  sobre jerarquías superiores; no admite fechas futuras.
- **Trabajadores sin celular**: "marcación supervisada" (origen `supervisada`)
  registrada por un responsable con motivo y auditoría.
- **Correcciones**: el trabajador solicita; quien regulariza aprueba/rechaza con
  respuesta (aprobar no modifica horas: se regulariza aparte).
- Sin sanciones ni descuentos automáticos.
- Hora: America/Lima = UTC-5 fijo (Perú no tiene horario de verano); se guardan
  `Timestamp` (UTC) y se convierte para mostrar (`core/time/lima_time.dart`).

Colecciones nuevas: `documentos`, `correos`, `movimientosPersonal`,
`restricciones`, `auditoria`, `horarios`, `terminales`, `qrTokens`,
`asistencias`, `estadoAsistencia`, `correcciones`. Índice compuesto nuevo en
`firestore.indexes.json`: `asistencias(uid ↑, entrada ↓)` (historial del
trabajador).

### Cambios en código previo (Fases 1–2)

- `PermissionService`/`AppRoute`: permisos y rutas nuevos; la ruta de inicio de
  cada rol no cambia (hay prueba).
- `sessionProvider`: si no hay perfil de personal, consulta `terminales/{uid}`
  (`TerminalAuthenticated`). `AuthRedirect` y `SessionResolver` lo contemplan.
- `AppUser` suma `nombres`, `horarioId`, `puedeRegularizar` (opcionales).
- `firestore.rules`: `usuarios` ya no es "solo lectura"; admite altas y
  ediciones validadas (jerarquía, formatos, unicidad, auditoría). Sigue siendo
  imposible crear superadmins o cambiar el propio rol (pruebas de Fase 2 intactas).
- `AndroidManifest.xml`: permisos `INTERNET` (faltaba en release) y `CAMERA`.
- `pubspec.yaml`: `mobile_scanner`, `qr_flutter`.
- `test/support/fakes.dart`: `FakeAuthRepository` usa `BehaviorSubject` (no
  pierde eventos por temporización).

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
- Alta de personal: ahora se hace desde la app con una instancia secundaria de
  Auth (ver Fase 3). `StaffProvisioningService` (contrato de Fase 2) queda sin
  uso; puede eliminarse o sustituirse por Cloud Functions si se activa Blaze.
- Revisar la plantilla del correo de restablecimiento en la consola de Firebase
  (idioma y remitente).
- Recomendado: rotar la clave de servicio si se comparte o se sospecha
  exposición.

## Pendientes de la Fase 3 (no hechos / por verificar)

1. **Desplegar** reglas e índices (no se desplegó nada; requiere tu
   autorización): `firebase deploy --only firestore`. Hasta entonces, contra
   Firebase real siguen las reglas de la Fase 2 y las pantallas nuevas fallarán
   por permisos. Después, ampliar `tools/verify_live.js` con casos de Fase 3 y
   probar a mano.
2. **No se probó contra Firebase real ni en un Android físico**: cámara,
   permiso de cámara, lectura de un QR real, creación de cuentas por instancia
   secundaria y envío del correo de contraseña. Solo hay pruebas unitarias, de
   widgets y de reglas con emulador; el APK debug compila.
3. Completar la ficha del Superadmin existente con
   `tools/complete_superadmin.js` (simulación por defecto; `--apply` escribe;
   conserva UID, correo, rol y `activo`). Requiere nombres, apellidos, tipo y
   número de documento y celular reales.
4. Probar en dispositivo real el flujo completo de activación (llegada de los
   dos correos, plantilla en español en la consola de Auth —no modificada—,
   apertura de WhatsApp). No se sabe con certeza si el enlace de contraseña
   también marca el correo como verificado; por eso se envían ambos correos.
   Sin rate limiting ni App Check; sin Cloud Functions (ver limitaciones).
5. Una terminal sin conexión no puede marcar (no hay cola offline, por diseño:
   no se aceptan marcaciones sin validar).
6. Aprobar una solicitud de corrección no regulariza automáticamente.
7. Editar documento/correo de un trabajador no está soportado (índices de
   unicidad inmutables); requeriría un flujo propio del Superadmin.

## Pendientes de producto

Lógica de pedidos, inventario, reportes, carta digital real, alta de personal
desde la app.
