> **Reemplazado el 2026-11-27.** El módulo «Inventario» y el rol Almacén se retiraron: usar `docs/CHECKLIST_FISICO_INVENTARIOS.md`. Este archivo se conserva solo como historial de la Fase 7.

# Checklist de prueba física — Fase 7 (inventario, recetas, costos, proveedores y compras)

Lo que las pruebas automatizadas **no** cubren: Firebase real y varios dispositivos. Nada de esto se ha ejecutado todavía.

**Requisito previo:** desplegar `firestore.rules` con autorización del propietario. Sin ellas las colecciones `insumos`, `movimientosInventario`, `proveedores`, `compras` y `recetas` rechazan todo. Hay consultas con `orderBy('creadoEn')` de un solo campo (sin índice compuesto). Usar datos de prueba, no los reales del restaurante.

Cuentas: un usuario de Almacén con entrada registrada, un Admin, un mesero y un cajero.

| # | Paso | Resultado esperado | Estado |
|---|------|--------------------|--------|
| 1 | Almacén abre «Inventario» → «Nuevo insumo» (Pollo, kg, mínimo 2, costo S/ 12.00) | Aparece con stock 0 kg | ☐ |
| 2 | «Entrada» de 10 kg | Stock 10 kg; en «Movimientos» queda con su autor y hora de Lima | ☐ |
| 3 | «Salida» de 1.5 kg con motivo; luego una salida mayor al stock | La primera baja el stock; la segunda muestra «No hay stock suficiente» y no cambia nada | ☐ |
| 4 | «Entrada», «Merma» y «Ajuste» (sumar y restar) sin motivo y con motivo | Sin motivo no deja guardar (también en entradas) | ☐ |
| 5 | Bajar el stock hasta el mínimo | Aparece «Stock bajo» y el filtro «Stock bajo (n)» lo lista; en 0, «Agotado» | ☐ |
| 6 | Dos usuarios sacan stock del mismo insumo a la vez | Ninguno deja el stock negativo ni inconsistente con los movimientos | ☐ |
| 7 | «Proveedores» → alta con RUC de 11 dígitos; RUC inválido; desactivar | RUC inválido se rechaza; el inactivo no sale al crear compras | ☐ |
| 8 | «Compras» → nueva compra de 2 insumos a un proveedor activo | Queda «Pendiente»; el stock no cambia | ☐ |
| 9 | «Recibir compra» | Pasa a «Recibida»; el stock sube en cada línea; el costo de cada insumo pasa al de la compra; hay un movimiento «Compra» por línea | ☐ |
| 10 | Intentar recibir otra vez la misma compra (otro dispositivo) | Mensaje «ya no está pendiente»; el stock no se duplica | ☐ |
| 11 | Cancelar una compra pendiente con motivo | Queda «Cancelada» con el motivo; ya no se puede recibir | ☐ |
| 12 | «Recetas» → crear la receta de un plato con 2 insumos | Muestra costo por porción, precio y margen; al cambiar el costo de un insumo, el costo de la receta cambia | ☐ |
| 13 | Almacén registra su salida y abre Inventario | Pierde el acceso en vivo; el Admin sigue entrando sin entrada | ☐ |
| 14 | Mesero, cajero y cocinero | No ven «Inventario»; abrir `/app/inventario` los redirige | ☐ |
| 15 | Consola de Firebase: intentar editar o borrar un movimiento o un insumo con un usuario de la app | Rechazado por las reglas | ☐ |
| 16 | Celular (≈ 400 px): recorrer las 5 pestañas y los diálogos | Sin desbordes; teclado no tapa los campos | ☐ |
| 17 | **Corrección de seguridad.** Almacén A crea una compra e intenta «Recibir compra» | Rechazada: «debe recibirla otra persona de Almacén»; Almacén B (u Admin) sí puede | ☐ |
| 18 | **Límite de 8 líneas en Firebase real:** crear una compra de 8 insumos distintos y recibirla con otro usuario; luego crear una de 9 | La de 8 se recibe sin «permission-denied» (si falla, el límite de accesos de producción es menor: bajar `InventoryValidation.maxLines` y las reglas); la de 9 no deja crearla | ☐ |
| 19 | Con un usuario de Almacén, editar un insumo existente | El costo aparece de solo lectura; con Admin se puede editar | ☐ |
| 20 | Recibir una compra y revisar en la consola los movimientos | Hay uno por línea con id `{compra}_{n}`, `linea`, `costoUnitario` y motivo vacío | ☐ |
| 21 | Con la consola de reglas (Simulador) o un cliente alterado: reescribir `stock` de un insumo sin movimiento nuevo | Rechazado | ☐ |

## Notas

- **El stock no se descuenta solo al vender.** Las recetas calculan el costo, pero la salida de insumos por consumo se registra a mano («Salida»). Descontar automáticamente al cobrar o preparar un pedido queda pendiente (ver README).
- Una compra admite hasta **8 insumos** (límite **provisional**, hay que validarlo en Firebase real: producción limita los accesos a documentos por lote) y un insumo no puede repetirse en la compra (las líneas van ordenadas por insumo).
- Las reglas desenrollan las 8 líneas por índice y contrastan cada movimiento de compra con su línea (insumo, cantidad y costo). Por el límite de 1000 expresiones, el insumo de cada línea se exige al **recibir**, no al crear.
- Toda entrada manual exige motivo; el costo de un insumo solo lo cambia una compra recibida o Admin/Superadmin.
