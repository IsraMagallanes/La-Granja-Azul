# Checklist físico: insumos, compras y utensilios

**Requisito previo:** reglas desplegadas con autorización del propietario (no
desplegadas todavía). Cuentas: Cocina, Mesero ×2, Cajero, Admin, Superadmin,
todos con entrada registrada salvo Admin/Superadmin. Los costos históricos de
insumos siguen pendientes de la migración autorizada aparte.

| # | Acción | Resultado esperado | ✔ |
|---|---|---|---|
| 1 | Cocina abre «Insumos» y crea un insumo | Se crea sin costo; no ve costos ni «Compras» | ☐ |
| 2 | Cocina registra una merma con motivo | Stock y movimiento coinciden | ☐ |
| 3 | Cocina abre `/app/compras` | Redirigida | ☐ |
| 4 | Admin fija el costo de un insumo | Aparece solo en pantallas de Admin | ☐ |
| 5 | Admin crea una compra de 5 líneas y la recibe | Recibida; stock y costos actualizados | ☐ |
| 6 | Intentar una compra de 6 líneas | La app no lo permite | ☐ |
| 7 | Cocina abre recetas | Ve ingredientes sin costos ni margen | ☐ |
| 8 | Admin da de alta un utensilio con costo | Aparece en el catálogo, con auditoría | ☐ |
| 9 | Admin registra el alta de existencias | Disponibles suben | ☐ |
| 10 | Mesero entrega utensilios a un compañero | Disponibles bajan, «en uso» y asignación suben | ☐ |
| 11 | Mesero registra devolución, pérdida y daño (con motivo) | Cantidades coherentes; sin negativos | ☐ |
| 12 | Mesero abre «Utensilios» | No ve costos ni valoración | ☐ |
| 13 | Admin revisa pérdidas | Ve el valor con el costo de la versión del movimiento | ☐ |
| 14 | Admin cambia el costo de un utensilio | Nueva versión; pérdidas viejas conservan su valor | ☐ |
| 15 | Cocina y Cajero abren `/app/utensilios` | Redirigidos | ☐ |
| 16 | Consola: editar o borrar un movimiento de utensilios | Rechazado | ☐ |
| 17 | Como Mesero, entregar utensilios a cualquier mesero activo | El selector lista todos los meseros activos (directorio mínimo: nombre y estado); no aparecen inactivos ni otros roles | ☐ |
| 18 | Proyecto separado: `limits_probe.js` | 5 líneas aceptada, 6 rechazada (ver `docs/LIMITES_FIRESTORE.md`) | ☐ |
| 19 | Celular (≈ 400 px): recorrer Insumos, Compras y Utensilios | Sin desbordes | ☐ |
