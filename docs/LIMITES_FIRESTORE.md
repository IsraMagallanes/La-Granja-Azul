# Límites de accesos de las reglas de Firestore

Firestore permite **10 accesos a documentos** (`get`, `exists`, `getAfter`,
`existsAfter`) por petición de un solo documento y **20** por lote o
transacción. **El emulador no aplica estos límites**, por lo que las pruebas
de reglas locales no los detectan. Este documento recoge el cálculo y cómo
comprobarlo de verdad **sin tocar producción**.

## Cálculo (criterio conservador)

`get()` y `getAfter()` del mismo documento se cuentan por separado; Firestore
puede contarlos una vez, así que el valor real es igual o menor.

| Escenario | Accesos | Límite | Resultado |
|---|---|---|---|
| Recibir compra de **n** líneas (Admin) | 3 + 3n | 20 | n=5 → **18** ✅ · n=6 → **21** ❌ |
| Entrega de utensilios (Mesero) | 6 | 20 | ✅ |
| Editar catálogo de utensilios con costo nuevo (Admin) | 4 | 20 | ✅ |
| Editar un insumo / fijar un costo | 2 / 1 | 10 | ✅ |
| Cocina marca «Listo» con 8 insumos (Fase 8B, **optimizada**) | 4 + 2n = **20** (antes 5 + 2n = 21) | 20 | ✅ sin margen: **validar en real** (con 7 insumos: 18) |

Desglose de la recepción: perfil del usuario (1), compra antes/después (2),
y por línea: movimiento, insumo y `costosInsumos` (3n). La regla del costo
(opción B) usa **un solo** `getAfter(costosInsumos/{id})` por línea y no
consulta `insumos`, por eso el máximo de **5 líneas** deja 2 accesos de margen.
El máximo está fijado de forma coherente en `firestore.rules`,
`InventoryValidation.maxLines` y `tools/lib/supply_costs_migration.js`.

## Fase 8B: qué se encontró y cómo se corrigió (Etapa 1)

La documentación de Firebase confirma que, además de los 20 accesos del lote, **cada
operación individual dentro del lote tiene un límite de 10**. Con el diseño anterior:

- La operación del pedido («→ Listo») consultaba perfil, jornada, el marcador y **los n
  movimientos**: 3 + n = **11 con 8 insumos** → superaba el límite de 10 por operación.
- El lote completo sumaba 5 + 2n = **21** (límite 20).

Correcciones (en `firestore.rules`, sin perder integridad):

1. **Cadena de movimientos:** el movimiento k exige `existsAfter` del k-1, así que basta
   comprobar el último (`consumptionDone` pasa de n accesos a 1). Por operación:
   pedido 4, marcador 4, movimiento 5, insumo 4.
2. **El marcador y la excepción ya no leen el pedido anterior:** prueban la transición con
   `getAfter(pedido).listoEn == request.time` (la regla del pedido solo permite pasar a «Listo»
   desde «preparando» y fija `listoEn = request.time`). Un acceso menos; un pedido ya «Listo»
   no admite un descuento nuevo (prueba incluida).

Resultado: 4 + 2n = 20 con n = 8 (Cocina) y también en el forzado de Admin (exento de la jornada).
**No hay margen:** si la prueba real falla con 8, bajar el máximo a 7 (constante
`ConsumptionPlanner.maxSupplies` + reglas `<= 8`) deja 18 accesos.

## Pruebas reproducibles

1. **Cálculo (sin red):** `node --test tools/limits_budget.test.js` verifica los
   totales anteriores y que reglas, app y migración usan el mismo máximo.
2. **Proyecto Firebase separado (real):** `tools/limits_probe.js`.
   - Crear un proyecto de pruebas (nunca `la-granja-azul-app`), habilitar
     Firestore y Authentication, y descargar una clave de cuenta de servicio.
   - Desplegar las reglas **en ese proyecto**: `firebase deploy --only firestore:rules --project <id>`.
   - `GOOGLE_APPLICATION_CREDENTIALS=<clave>` y `LIMITS_API_KEY=<web api key>`.
   - `node tools/limits_probe.js --project <id> --i-confirm-separate-project`
   - Espera: compra de 5 líneas **aceptada**, de 6 **rechazada**, entrega de
     utensilios **aceptada**, «Listo» con 8 insumos **aceptada** y con 9 **rechazada**. Sale con código 1 si algo difiere. Limpia lo
     sembrado salvo con `--keep`.
   - El script **rechaza** el id de producción y exige la confirmación explícita.

**Estado:** la sonda está escrita y verificada solo en sintaxis y en el rechazo
de producción. **No se ha ejecutado contra ningún proyecto real**: queda
pendiente de que el propietario cree el proyecto de pruebas.
