# Checklist de prueba física — Fase 2

Lo que las pruebas automatizadas **no** cubren: Firebase real y dispositivos reales. Nada de esto se ha ejecutado todavía. Marca cada punto con la fecha y quién lo probó.

**Requisito previo:** desplegar las reglas con autorización del propietario (`firebase deploy --only firestore`). Hasta entonces, contra Firebase real siguen las reglas anteriores: no existe la condición de asistencia ni la colección `solicitudesEliminacionTerminal`. Antes de desplegar, seguir el orden seguro de `docs/ESTADO_PROYECTO.md` (verificación del correo del Superadmin).

Datos de prueba: un Superadmin, un Admin, un mesero y un cocinero reales (o de prueba) con la ficha completa, y un celular por trabajador (la asistencia se registra escaneando el QR de Superadmin, Admin o Cajero; el sistema antiguo de terminales fue retirado) autorizada.

## 1. Asistencia como condición de acceso (Android + Firebase real)

| # | Paso | Resultado esperado | OK |
|---|------|--------------------|----|
| 1 | Mesero inicia sesión **sin** haber registrado entrada | Aterriza en «Mi asistencia» con el aviso «Registra tu entrada…». El menú no muestra Mesas, Pedidos ni Mesero | ☐ |
| 2 | Mesero escribe a mano `/app/mesas` o `/app/pedidos` (web) | Lo devuelve a «Mi asistencia» | ☐ |
| 3 | Mesero abre «Escanear asistencia» y escanea el QR que muestra el Cajero o el Admin (sin elegir entrada/salida) | La app confirma «Entrada registrada» con la hora del servidor | ☐ |
| 4 | Sin cerrar la app del mesero | En segundos aparecen Mesas y Pedidos en su menú, sin volver a iniciar sesión | ☐ |
| 5 | Mesero abre una mesa y toma un pedido | Funciona (reglas de mesas y pedidos con la jornada abierta) | ☐ |
| 6 | Mesero vuelve a escanear un QR vigente (la app registra la salida sola) | Pierde el acceso en vivo: lo saca del módulo y desaparecen Mesas y Pedidos | ☐ |
| 7 | Con la salida registrada, el mesero intenta leer pedidos (p. ej. recargando la web) | No puede leer ni escribir pedidos ni mesas | ☐ |
| 8 | Cocinero: repetir 1, 3, 4 y 6 | Mismo comportamiento (su módulo es Cocina) | ☐ |
| 9 | Admin y Superadmin inician sesión **sin** registrar entrada | Acceden a Dashboard, Mesas y Pedidos con normalidad | ☐ |
| 10 | Un pedido queda abierto al registrar la salida del mesero | El mesero ya no lo ve; el Admin sí puede verlo y editarlo | ☐ |
| 11 | Mesero olvida registrar la salida | Conserva el acceso hasta que alguien con permiso regularice la jornada (no hay cierre automático) | ☐ |

## 2. Permisos y pantalla Roles

| # | Paso | Resultado esperado | OK |
|---|------|--------------------|----|
| 12 | Superadmin abre «Roles y permisos» | Ve la matriz por rol (solo lectura) y la condición de asistencia de cada uno | ☐ |
| 13 | Admin intenta entrar a `/app/roles` | Lo devuelve a su inicio | ☐ |
| 14 | Admin consulta si un documento tiene restricción al dar de alta | Ve el aviso informativo (sigue pudiendo leerlo) | ☐ |

## 3. Eliminación definitiva de una terminal

**Retirada (2026-11-27):** el sistema antiguo de terminales ya no existe en la app; se retiró junto con sus datos (ver `docs/RETIRO_CUENTAS_TERMINAL.md`). Estos pasos (15 a 22) quedan sin efecto.

## Notas

- Las reglas y la matriz se contrastan en el emulador (`npm run test:rules` en `tools/`); esta lista es para lo que solo se ve con Firebase real y dispositivos.
- Reportar cualquier desajuste junto con la hora aproximada y el correo del usuario de prueba, sin contraseñas.

## Sesión de pruebas del 2026-11-19 (Claude Code, equipo de desarrollo)

**Entorno disponible:** Windows 11, Chrome y Edge, Android SDK instalado **sin** emulador creado y **sin** teléfono ni tablet conectados; sin clave de servicio de Admin SDK ni contraseñas de cuentas de prueba; las reglas nuevas **no están desplegadas** (no autorizado) y la app no tiene modo emulador. Por eso ningún paso de esta lista pudo ejecutarse contra Firebase real y **ninguna casilla ☐ se marcó**.

**Comprobaciones reales realizadas (no sustituyen los pasos):**
- `flutter build web --release`: compila (con `image_picker`, `image` y los módulos de las fases 2–4). Aprobado.
- `flutter build apk --debug`: compila. Aprobado.
- Pruebas automatizadas de la fase: ver README (registro de fases).

**Estado por paso:** 1–11 *bloqueados* (necesitan Android + terminal + cuentas reales + reglas desplegadas); 12–14 *bloqueados* (necesitan sesión de Superadmin/Admin real); 15–17 *bloqueados* (app con Firebase real); 18–22 *bloqueados* (necesitan la clave de servicio en el equipo del propietario y una terminal real; el script solo se probó en el emulador con `delete_terminal.test.js`, automatizado).

**Qué necesito de ti:** (1) autorizar el despliegue de `firestore.rules` (`firebase deploy --only firestore:rules --project la-granja-azul-app`) siguiendo el orden de `docs/ESTADO_PROYECTO.md`; (2) conectar un teléfono Android con depuración USB o decirme que cree un emulador; (3) pasarme por un canal seguro (o iniciar tú sesión en el equipo) cuentas de prueba de Superadmin, Admin, mesero y cocina; (4) para 18–22, ejecutar los comandos del script tú mismo con tu clave de servicio.
