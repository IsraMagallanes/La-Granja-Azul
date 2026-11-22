# Checklist de prueba física — Fase 4 (mesas, pedidos y reservaciones)

Lo que las pruebas automatizadas **no** cubren: Firebase real, dos dispositivos a la vez y selectores de fecha/hora reales. Nada de esto se ha ejecutado todavía.

**Requisito previo:** desplegar `firestore.rules` con autorización del propietario (`firebase deploy --only firestore:rules`). Con las reglas anteriores, cancelar un pedido con motivo y toda la colección `reservaciones` darían `permission-denied`. No hay índices nuevos.

Usa cuentas existentes: un Admin, dos Meseros con la entrada registrada y un Cajero con la entrada registrada.

| # | Paso | Resultado esperado | OK |
|---|------|--------------------|----|
| 1 | Mesero: «Reservaciones» → «Nueva reservación». Mesa de 4, cliente, teléfono, 3 personas, hoy dentro de 3 h | Se guarda como «Pendiente» y aparece en «Hoy» | ☐ |
| 2 | Sin elegir mesa ni hora, pulsar «Guardar» | Marca los campos obligatorios; no guarda | ☐ |
| 3 | Reservar 5 personas en la mesa de 4 | Mensaje «La mesa 4 es para 4 personas como máximo» | ☐ |
| 4 | Reservar la misma mesa 1 h después de la anterior | Mensaje de cruce con la hora de la reserva existente | ☐ |
| 5 | Reservar la misma mesa 2 h exactas después | Se acepta | ☐ |
| 6 | Reservar una hora pasada | Rechaza («fecha y hora futuras») | ☐ |
| 7 | En Mesas, mirar la mesa reservada | Muestra «Reservada HH:mm · cliente» (hora de Lima) en la ventana del admin y del otro mesero | ☐ |
| 8 | «Confirmar» la reserva; luego «Editar» el teléfono | Pasa a «Confirmada» y la edición conserva el estado | ☐ |
| 9 | Cajero abre «Reservaciones» | Ve la lista, sin botones de gestión | ☐ |
| 10 | «Sentar y abrir pedido» en una confirmada | Abre el pedido de la mesa; la reserva pasa a «Cumplida» con «Ver pedido» | ☐ |
| 11 | Repetir 10 con la mesa ocupada por otro pedido | Error comprensible; la reserva sigue «Confirmada» | ☐ |
| 12 | Cancelar una reserva sin motivo, luego con motivo | Exige motivo (3–200 caracteres); queda «Cancelada» y muestra el motivo | ☐ |
| 13 | Reserva con la hora ya pasada | Aparece «No asistió»; antes de la hora no aparece | ☐ |
| 14 | Dos meseros: uno confirma mientras el otro edita la misma reserva | Ninguno se rompe; gana el último guardado válido | ☐ |
| 15 | Mesero: «Cancelar pedido» en un pedido abierto | Pide el motivo; la mesa queda libre; el detalle muestra «Motivo de cancelación» | ☐ |
| 16 | Admin cancela el pedido abierto de un mesero | Funciona y queda como cancelado por el admin | ☐ |
| 17 | Pedido registrado: buscar cancelar o editar | No hay botones; el pedido sigue inmutable | ☐ |
| 18 | Mesero registra la salida y abre «Reservaciones» | Pierde el acceso (módulo operativo); el Admin no | ☐ |
| 19 | Consola de Firebase: `reservaciones/{id}` y `pedidos/{id}` cancelado | Campos `motivoCancelacion` y `canceladoPor` correctos; ninguna reserva borrada | ☐ |

## Notas

- El cruce de horarios de una misma mesa lo avisa la app; las reglas de Firestore no pueden consultar otras reservas. Dos personas reservando la misma mesa y hora en el mismo instante podrían crear ambas. Para el volumen del local es aceptable; si no, la alternativa es un documento «candado» por mesa y bloque horario.
- «Sentar» abre el pedido y luego marca la reserva: si la segunda escritura falla, el pedido queda abierto y la reserva «Confirmada» (la app lo avisa).

## Sesión de pruebas del 2026-11-19 (Claude Code, equipo de desarrollo)

**Entorno disponible:** Windows 11, Chrome y Edge, Android SDK instalado **sin** emulador creado y **sin** teléfono ni tablet conectados; sin clave de servicio de Admin SDK ni contraseñas de cuentas de prueba; las reglas nuevas **no están desplegadas** (no autorizado) y la app no tiene modo emulador. Por eso ningún paso de esta lista pudo ejecutarse contra Firebase real y **ninguna casilla ☐ se marcó**.

**Comprobaciones reales realizadas (no sustituyen los pasos):**
- `flutter build web --release`: compila (con `image_picker`, `image` y los módulos de las fases 2–4). Aprobado.
- `flutter build apk --debug`: compila. Aprobado.
- Pruebas automatizadas de la fase: ver README (registro de fases).

**Estado por paso:** 1–19 *bloqueados*: todos necesitan las reglas nuevas desplegadas (la colección `reservaciones` y la cancelación con motivo no existen en las reglas de producción) y cuentas reales de Admin, dos meseros y cajero con la entrada registrada. Lo comprobado: la compilación.

**Qué necesito de ti:** autorizar el despliegue de reglas, cuentas de prueba (Admin, 2 meseros, cajero) y que el administrador de la consola de Firebase confirme que puedo crear y borrar datos de prueba, o crear un proyecto Firebase aparte para pruebas.
