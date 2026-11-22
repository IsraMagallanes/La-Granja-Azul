# Checklist de prueba física — Fase 6 (caja y ventas)

Lo que las pruebas automatizadas **no** cubren: Firebase real, varios dispositivos a la vez y conexiones interrumpidas. Nada de esto se ha ejecutado todavía.

**Requisito previo:** desplegar `firestore.rules` con autorización del propietario (`firebase deploy --only firestore:rules`). Sin las reglas nuevas, `pagos`, `cajas`, `cajaActiva` y `movimientosCaja` no existen y todo cobro es rechazado. Hay una consulta nueva con filtro `cajaId` y otra con filtro `creadoEn` (un solo campo, sin índice compuesto): si la consola pidiera un índice, créalo desde el enlace del error.

Cuentas: un cajero y un mesero con entrada registrada, un cocinero y un Admin. Usar datos de prueba, no datos reales del restaurante.

| # | Paso | Resultado esperado | Estado |
|---|------|--------------------|--------|
| 1 | Cajero con entrada abre «Caja» → «Caja» → fondo S/ 100.00 → «Abrir caja» | Caja abierta; aparece «Caja abierta» en el riel; `cajas/{id}` y `cajaActiva/actual` existen | ☐ |
| 2 | Un segundo usuario de caja o el Admin intenta abrir otra caja | Mensaje «Ya hay una caja abierta» | ☐ |
| 3 | Flujo completo: mesero registra pedido, cocina prepara y marca listo, mesero entrega | En Caja → «Cobrar» aparece la mesa con su total | ☐ |
| 4 | Antes de entregar: mirar «Cobrar» | El pedido está en «Aún no entregados», sin botón de cobro | ☐ |
| 5 | Cobrar en efectivo con S/ 60 sobre un total de S/ 51 | Muestra «Vuelto: S/ 9.00»; confirma; mesa libre en Mesas; pedido «Pagado» | ☐ |
| 6 | Cobrar otro pedido con tarjeta, Yape y Plin | Cobra el total exacto, sin vuelto | ☐ |
| 7 | Efectivo menor al total | «Falta S/ x» y no deja confirmar | ☐ |
| 8 | Dos cajeros abren el mismo pedido y cobran a la vez | Solo uno lo logra; el otro ve «ya fue cobrado» | ☐ |
| 9 | Cortar la red del dispositivo justo al confirmar el cobro; luego restaurarla | O se cobró todo (pago + pedido pagado + mesa libre) o nada; nunca la mesa libre sin pago ni pago sin cerrar el pedido | ☐ |
| 10 | Pulsar «Confirmar cobro» dos veces seguidas | Un solo pago en `pagos/{pedidoId}` | ☐ |
| 11 | Registrar un egreso (S/ 20, «Hielo») y un ingreso | Aparecen en «Movimientos»; el efectivo esperado cambia | ☐ |
| 12 | Cerrar la caja contando exactamente lo esperado | Cierra sin nota; «Cuadra» en Historial; ya se puede abrir otra caja | ☐ |
| 13 | Cerrar otra caja contando de menos | Exige motivo; Historial marca «Faltan S/ x» | ☐ |
| 14 | Con la caja cerrada, intentar cobrar | Botones deshabilitados y aviso «La caja está cerrada» | ☐ |
| 15 | Cajero registra su salida | Pierde el acceso a Caja en vivo; el Admin sigue entrando sin entrada | ☐ |
| 16 | Admin y Superadmin abren «Caja» desde su menú | Ven las 4 secciones y pueden cobrar y cerrar | ☐ |
| 17 | Mesero y cocinero | No ven el módulo Caja; abrir `/app/caja` los redirige | ☐ |
| 18 | «Ventas»: Hoy / Caja actual / Todas | Totales por método coinciden con lo cobrado | ☐ |
| 19 | Consola de Firebase: `pagos/{pedidoId}` | `cobradoPor`, `cobradoPorNombre`, `creadoEn` (hora del servidor), método, recibido y vuelto | ☐ |
| 20 | Celular (≈ 400 px): recorrer las 4 secciones | Barra inferior; sin desbordes; botones táctiles cómodos | ☐ |
| 21 | Intentar editar o borrar un pago o una caja cerrada desde la consola con un usuario de la app | Rechazado por las reglas | ☐ |

## Notas

- No hay anulación ni devolución de cobros: un pago es definitivo. Corregirlo exigiría un flujo con autorización y auditoría que queda pendiente.
- El total del cobro lo calcula la app (las reglas no pueden sumar los detalles de un pedido); las reglas sí validan método, vuelto, quién cobra, hora del servidor, estado del pedido y la liberación de la mesa.
- No hay impresión de comprobantes ni facturación electrónica.
