# Checklist de prueba física — Fase 8 (reportes y estadísticas)

Lo que las pruebas automatizadas **no** cubren: Firebase real con datos reales y el uso de lecturas (cuota de Spark). Nada de esto se ha ejecutado todavía.

**Requisito previo:** reglas de las fases 6 y 7 desplegadas (los reportes leen `pagos`, `compras`, `movimientosInventario`, `insumos`, `recetas`, `asistencias` y `pedidos/*/detalles`; la Fase 8 **no cambia las reglas**). Hay consultas por rango de un solo campo (`creadoEn`, `recibidoEn`, `entrada`), sin índice compuesto. Cuentas: un Admin o Superadmin, y un mesero, un cajero y un cocinero para comprobar que no entran. Tener algunos cobros, compras y asistencias de prueba.

| # | Paso | Resultado esperado | Estado |
|---|------|--------------------|--------|
| 1 | Admin abre «Reportes» → «Ventas», periodo «Hoy» | Total, n.º de ventas, ticket promedio y hora pico coinciden con lo cobrado en Caja (Caja → Ventas → Hoy) | ☐ |
| 2 | Cambiar a «Últimos 7 días», «Últimos 30 días» y «Este mes» | Las cifras cambian; «Por día» lista cada día de Lima; coincide con Caja → Ventas | ☐ |
| 3 | Cobrar algo pasadas las 19:00 de Lima (00:00 UTC) y mirar «Hoy» | Cuenta en el día de Lima, no en el siguiente | ☐ |
| 4 | Revisar «Por método de pago» y «Por cajero» | Las sumas cierran con el total; cada cajero con sus ventas | ☐ |
| 5 | «Platos» → «Analizar platos vendidos» | Ranking por cantidad; ingreso por plato coincide con los pedidos; sin pulsar el botón no se lee ningún detalle | ☐ |
| 6 | Platos con receta y sin receta | Con receta: costo y margen; sin receta: «sin receta» y aviso de cuántos quedan fuera del margen | ☐ |
| 7 | Con más de 300 pedidos cobrados en el periodo (si se puede) | Aviso «Solo se analizaron los 300 pedidos más recientes» | ☐ |
| 8 | «Asistencia» | Jornadas y horas por persona; una jornada abierta aparece como «abierta» y no suma horas; coincide con Asistencia (admin) | ☐ |
| 9 | «Inventario» | Valor del stock = suma stock × costo de los insumos activos; compras recibidas y mermas del periodo; lista de stock bajo | ☐ |
| 10 | Botón «Actualizar» de cada pestaña | Vuelve a leer y refleja un cobro o compra nuevos | ☐ |
| 11 | Mesero, cajero y cocinero | No ven «Reportes» en el menú; abrir `/app/reportes` los redirige | ☐ |
| 12 | Consola de Firebase → Uso | Abrir los reportes unas 10 veces no excede por mucho las lecturas esperadas (ventas ≈ n.º de cobros; platos ≈ n.º de pedidos) | ☐ |
| 13 | Celular (≈ 400 px): recorrer las 4 pestañas y los periodos | Sin desbordes; los filtros de periodo se acomodan en varias líneas | ☐ |

## Notas

- Los reportes **no se actualizan en vivo** (salvo Asistencia): se leen al abrir o al pulsar «Actualizar», para cuidar la cuota de lecturas.
- El costo y el margen de platos usan el costo **vigente** de los insumos, no el de la fecha de la venta; son estimaciones.
- No hay exportación (CSV/PDF), gráficos de línea ni comparación entre periodos.
- Un cajero puede leer los pagos por las reglas de Caja, pero no ve el módulo Reportes.
