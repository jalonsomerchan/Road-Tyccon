# Renovación visual: cruces, coches y ciudades

Arte generado con la herramienta integrada **ImageGen**, sin API externa.

- `roads-{a,b,c,d}-raw.png`: cuatro láminas de seis tipos de carretera por cuatro formas. Incluyen los 24 tipos, con recta, curva, T y cruce de cuatro brazos.
- `cars-raw.png`: ocho coches cenitales, orientados al norte. El juego gira el sprite según la dirección del viaje.
- `villa`, `slate_house`, `timber_house`, `apartment`, `brick_block`, `warehouse`, `civic`, `park`: ocho imágenes individuales de edificios y parque.
- `*-processed/`: extracción, transparencia y QC del procesador de generate2dsprite.
- `road-registration.json`: centros y escalas usados al registrar los puertos de cada pieza.
- `prompts.md`: especificaciones de los prompts usados.
- `sources.json`: procedencia de las imágenes originales, que se conservan.

Los recursos finales están en `assets/sprites/roads-v5/`, `assets/sprites/vehicles-v2/` y `assets/sprites/city-v2/`. Se conservan las versiones anteriores como fuentes.

`tools/prepare_visual_refresh.py` solo recorta, elimina magenta, extrae, escala con vecino más próximo, registra y compone materiales generados. Las seis filas/columnas de píxeles de cada conexión abierta proceden de su recta correspondiente. Los extremos opuestos comparten el mismo perfil y las uniones se comprueban píxel a píxel en `tests/visual_refresh.gd`.

La generación urbana usa una semilla y un estilo persistentes por ciudad. Varía arquitectura, densidad de solares, jardines, orientación de edificios y calles internas. Son decisiones visuales; las dimensiones, accesos y generación de viajes mantienen sus reglas. Los guardados antiguos reciben identidades visuales deterministas al cargar.
