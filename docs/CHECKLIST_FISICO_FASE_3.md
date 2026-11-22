# Checklist de prueba física — Fase 3 (productos y carta digital)

Lo que las pruebas automatizadas **no** cubren: selector de fotos real, Firebase real y la vista en dispositivos. Nada de esto se ha ejecutado todavía.

**Requisito previo:** desplegar las reglas con autorización del propietario (`firebase deploy --only firestore`). Hasta entonces, contra Firebase real siguen las reglas anteriores: no existe `cartaFotos` y la URL de imagen sigue siendo obligatoria, así que guardar una foto o un plato sin URL fallaría por permisos.

| # | Paso | Resultado esperado | OK |
|---|------|--------------------|----|
| 1 | Admin (web) abre Carta → Nuevo plato → «Elegir foto» y elige una foto de varios MB | Muestra «Procesando…» unos segundos y luego la vista previa; el botón pasa a «Cambiar foto» | ☐ |
| 2 | Guardar el plato sin escribir URL | Se guarda; en la lista aparece con su miniatura | ☐ |
| 3 | En la consola de Firebase, `cartaFotos/{id del plato}` | Existe, `tipo: image/jpeg`, `foto` ≤ 100 KB | ☐ |
| 4 | Repetir 1–2 desde Android (galería del teléfono) con una foto tomada con la cámara en vertical | La foto queda derecha (no girada) | ☐ |
| 5 | Editar el plato → «Cambiar foto» y guardar | La carta pública muestra la foto nueva (tras recargar la página) | ☐ |
| 6 | Editar el plato → «Quitar foto» y guardar | Desaparece `cartaFotos/{id}`; el plato vuelve a su URL o al marcador | ☐ |
| 7 | Elegir un archivo que no es imagen (p. ej. un PDF renombrado) | Mensaje «No se pudo leer la imagen…»; no cambia nada | ☐ |
| 8 | Interruptor de disponibilidad en la lista de administración | Cambia al instante; la carta pública lo refleja sin recargar | ☐ |
| 9 | Carta pública (sin sesión) en celular, tablet y PC | Fotos reales visibles; los platos agotados van al final, atenuados y con «No disponible» | ☐ |
| 10 | Tocar un plato en la carta pública | Abre la ficha: foto grande, descripción completa, precio y disponibilidad; «Cerrar» la cierra | ☐ |
| 11 | Mesero (con la entrada registrada) intenta guardar una foto o editar un plato | No puede (las reglas lo rechazan) | ☐ |
| 12 | Carta con 20–30 platos con foto, en datos móviles | Carga razonable; las fotos aparecen a medida que llegan, sin bloquear la lista | ☐ |
| 13 | Consola de Firebase → Uso de Firestore tras una semana de pruebas | Lecturas y transferencia lejos de las cuotas de Spark (50 000 lecturas/día; 10 GiB/mes de salida) | ☐ |

## Notas

- Cada visita a la carta pública descarga una foto por plato mostrado (≈ 40–90 KB cada una). Con ~30 platos son 1–3 MB por visita; 10 GiB/mes de salida alcanza para unos miles de visitas. Si el tráfico crece, alternativas sin Blaze: alojar las fotos con Firebase Hosting o en una URL externa (el campo URL sigue funcionando).
- Una foto cambiada no se actualiza en la carta de quien ya la tenía abierta hasta que recargue.

## Sesión de pruebas del 2026-11-19 (Claude Code, equipo de desarrollo)

**Entorno disponible:** Windows 11, Chrome y Edge, Android SDK instalado **sin** emulador creado y **sin** teléfono ni tablet conectados; sin clave de servicio de Admin SDK ni contraseñas de cuentas de prueba; las reglas nuevas **no están desplegadas** (no autorizado) y la app no tiene modo emulador. Por eso ningún paso de esta lista pudo ejecutarse contra Firebase real y **ninguna casilla ☐ se marcó**.

**Comprobaciones reales realizadas (no sustituyen los pasos):**
- `flutter build web --release`: compila (con `image_picker`, `image` y los módulos de las fases 2–4). Aprobado.
- `flutter build apk --debug`: compila. Aprobado.
- Pruebas automatizadas de la fase: ver README (registro de fases).

**Estado por paso:** 1–13 *bloqueados*. Los pasos 1–7 requieren el selector real de fotos (Android/web) y escribir en Firebase real con reglas desplegadas; 8–10 y 12 requieren la carta real y dispositivos; 11 una cuenta de mesero real; 13 una semana de uso. Lo comprobado: la compilación web y Android con las dependencias de fotos.

**Qué necesito de ti:** autorizar el despliegue de reglas (necesario para `cartaFotos` y la URL opcional), una cuenta de Admin de prueba y un dispositivo Android o emulador; para el paso 13, revisar tú el uso de Firestore en la consola tras una semana.
