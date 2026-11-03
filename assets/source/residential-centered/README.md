# Calle residencial centrada

Dos imágenes nuevas generadas con la herramienta integrada ImageGen: `geometry-raw.png` y `conditions-raw.png`. Los prompts están en `geometry-prompt.txt` y `conditions-prompt.txt`. La versión anterior se conserva en `previous/`.

Los cuatro sprites activos se guardan en `assets/sprites/roads-v5/residential/`. Los nueve estados están en `assets/sprites/road-conditions/residential/`. Se utilizan también en el atlas de calles internas de las ciudades.

`tools/prepare_residential_centered.py` registra la calzada respecto al eje de la casilla, normaliza sus puertos y reutiliza las franjas de conexión de la recta. La recta es simétrica respecto a x=31,5 en una imagen de 64 píxeles y la marca central ocupa los píxeles 31 y 32. El procesador solo recorta, transforma, alinea y compone píxeles generados; no dibuja el arte.

El generador general `tools/prepare_visual_refresh.py` vuelve a aplicar este kit al reconstruir las carreteras, para no restaurar accidentalmente la versión desplazada.

- `registration.json`: dimensiones, eje y transformaciones de las piezas.
- `preview.png`: cuatro piezas y una unión de prueba.
- `conditions-preview.png`: estados y rotonda.
- `tests/residential_centered.gd`: simetría, marca central, puertos de estados y atlas urbano.
- `tests/visual_refresh.gd`: uniones de rectas, curvas y cruces de todos los tipos.
