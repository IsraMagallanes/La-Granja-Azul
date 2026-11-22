# Checklist de prueba física — Fase 5 (cocina)

Lo que las pruebas automatizadas **no** cubren: Firebase real, la tablet de cocina y varios dispositivos a la vez. Nada de esto se ha ejecutado todavía (ver el estado de las pruebas físicas de las fases 2 a 4 en el README).

**Requisito previo:** desplegar `firestore.rules` con autorización del propietario (`firebase deploy --only firestore:rules`). Con las reglas anteriores, registrar un pedido no lo envía a cocina y el tablero no puede mover nada. No hay índices nuevos. Los pedidos registrados antes de la Fase 5 aparecen como «Pendiente».

Cuentas: un cocinero y un mesero con la entrada registrada, y un Admin.

| # | Paso | Resultado esperado | Estado |
|---|------|--------------------|--------|
| 1 | Mesero abre una mesa, añade 2 platos (uno con observación) y pulsa «Registrar pedido» | El pedido aparece en la tablet de cocina, columna «Pendiente», en segundos y sin recargar | ☐ |
| 2 | Ver el ticket en la tablet (horizontal y vertical) | Mesa, mesero, hora de registro (Lima), cada plato con cantidad y observación, minutos de espera | ☐ |
| 3 | Cocinero pulsa «Empezar a preparar» | El ticket pasa a «En preparación»; el mesero ve «Cocina: En preparación» en su pedido | ☐ |
| 4 | Cocinero pulsa «Marcar listo» | Pasa a «Listo» con el aviso «Listo: espera al mesero»; el mesero ve «Cocina: Listo» | ☐ |
| 5 | Mesero abre el pedido → «Marcar entregado» | El ticket sale del tablero; el detalle muestra «Cocina: Entregado» | ☐ |
| 6 | Varios pedidos con horas distintas | El más antiguo va primero; el tiempo sube solo cada 30 s; pasa a color de atención a los 15 min y de retraso a los 30 min | ☐ |
| 7 | Dos cocineros pulsan «Empezar a preparar» sobre el mismo ticket a la vez | Solo uno lo logra; el otro ve un mensaje claro y el tablero se actualiza | ☐ |
| 8 | Otro mesero abre el pedido ajeno (si lo puede ver) o el mesero intenta mover un ticket en cocina | No ve «Marcar entregado» ni botones de cocina | ☐ |
| 9 | Cocinero registra su salida y mira el tablero | Pierde el acceso en vivo (módulo operativo); el Admin sigue viéndolo | ☐ |
| 10 | Admin abre «Cocina» sin registrar entrada | Ve el tablero y puede mover tickets (incluida la entrega) | ☐ |
| 11 | Cajero abre Pedidos | Ve el estado de cocina, sin botones de gestión; no tiene el módulo Cocina | ☐ |
| 12 | Celular (≈ 400 px): abrir Cocina | Una columna a la vez con filtros «Pendiente (n) / En preparación (n) / Listo (n)» | ☐ |
| 13 | Cancelar un pedido abierto y registrar otro | El cancelado no aparece en cocina; el registrado sí | ☐ |
| 14 | Consola de Firebase: `pedidos/{id}` entregado | `estadoCocina`, `registradoEn`, `preparandoEn`, `cocinaPor`, `listoEn`, `entregadoEn` con hora del servidor | ☐ |
| 15 | Tablet con la pantalla encendida durante un servicio completo | Sin cortes; los pedidos nuevos llegan solos | ☐ |

## Notas

- La cocina escucha todos los pedidos (no solo los registrados) y filtra en la app; con mucho historial convendrá una consulta por estado (Fase 10).
- No hay aviso sonoro ni impresión de tickets.
- Un mesero que olvidó marcar «entregado» deja el ticket en la columna «Listo» hasta que él o un Admin lo entregue.
