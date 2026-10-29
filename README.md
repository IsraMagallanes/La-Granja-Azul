# granja_azul

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

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
