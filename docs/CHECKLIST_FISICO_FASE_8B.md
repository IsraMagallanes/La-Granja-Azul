# Checklist de prueba física — Fase 8B (descuento automático de inventario)

Lo que las pruebas automatizadas **no** cubren: la transacción real de la app contra Firestore, el límite de accesos de producción y el uso desde Cocina. Nada de esto se ha ejecutado.

**Requisito previo:** desplegar `firestore.rules` con autorización del propietario. Datos de prueba: 2 insumos con stock, un plato con receta (2 insumos), un plato sin receta, cuentas de Cocina (con jornada), Mesero y Admin.

| # | Paso | Resultado esperado | Estado |
|---|------|--------------------|--------|
| 1 | Mesero registra un pedido de 2 porciones del plato con receta; Cocina lo pasa a «Preparando» y luego «Marcar listo» | Pasa a «Listo»; el stock de cada insumo baja receta × 2; Movimientos muestra un «Consumo» por insumo con «Pedido …», responsable y hora | ☐ |
| 2 | En la consola, abrir `descuentosInventario/{pedido}` | Existe con n.º de insumos, platos sin receta, responsable y hora | ☐ |
| 3 | Dos cocineros pulsan «Marcar listo» a la vez en dos dispositivos | Solo uno descuenta; el otro ve el aviso; el stock baja una sola vez | ☐ |
| 4 | Pedido que necesita más stock del que hay, con Cocina | «Marcar listo» muestra «No hay stock suficiente…» con los insumos; el pedido sigue «Preparando» y el stock no cambia | ☐ |
| 5 | Pedido solo con el plato sin receta | Pasa a «Listo» sin movimientos; el marcador tiene `platosSinReceta` > 0 | ☐ |
| 6 | Receta con un insumo desactivado | Pasa a «Listo»; ese insumo no se descuenta; marcador con `insumosOmitidos` | ☐ |
| 7 | **Límite de accesos:** pedido que consuma 8 insumos distintos | Pasa a «Listo» sin «permission-denied». Si falla, bajar `ConsumptionPlanner.maxSupplies` y las reglas | ☐ |
| 8 | Pedido que necesite 9 insumos | Mensaje «usa más de 8 insumos»; no cambia nada | ☐ |
| 9 | Cancelar un pedido ya «Listo» | El stock **no** se repone; Cocina o la administración reponen con un ajuste con motivo | ☐ |
| 10 | Cocina intenta ver Movimientos/Inventario | No tiene el módulo; solo calcula el descuento | ☐ |
| 11 | Admin marca «Listo» un pedido | Descuenta igual, con su nombre como responsable | ☐ |
| 12 | Un pedido que ya estaba «Listo» antes del despliegue | No descuenta (ver README) | ☐ |
| 13 | **Forzado:** con Admin, repetir el paso 4 | Aparece «Falta stock» con los faltantes y un campo de motivo | ☐ |
| 14 | Motivo de 9 caracteres, vacío o solo espacios | No deja forzar; con 10 o más, sí | ☐ |
| 15 | Confirmar el forzado | Pasa a «Listo»; cada insumo baja hasta 0 como máximo (nunca negativo); un insumo que estaba en 0 no genera movimiento | ☐ |
| 16 | Consola: `excepcionesInventario/{pedido}` y `descuentosInventario/{pedido}` | La excepción tiene motivo, faltantes (necesario, descontado, faltante), tu uid y nombre y la hora; el marcador tiene `forzado: true` | ☐ |
| 17 | Intentar forzar el mismo pedido otra vez (otro dispositivo) o con otro Admin | Rechazado; el stock no vuelve a bajar | ☐ |
| 18 | Con Cocina y Mesero | No aparece la opción de forzar; Cocina no puede leer `excepcionesInventario` | ☐ |
| 19 | Forzado de un pedido con 8 insumos faltantes | Pasa sin «permission-denied» (si falla, el lote de 8 con excepción supera el límite de producción: bajar `maxSupplies`) | ☐ |
