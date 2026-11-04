# Terreno

`terrain-atlas-generated.png` conserva la primera renovación de las 16 texturas y `terrain-atlas-before.png` conserva la hoja original.

La hierba base se refinó después por separado. `terrain-grass-generated.png` y `terrain-grass-generated.prompt.txt` guardan la fuente y el prompt de la textura más limpia aplicada a los sprites 1 y 4. Los sprites siguen siendo de 64x64 y la hoja `assets/sprites/terrain/sheet-transparent.png` se reconstruye a partir de los archivos individuales.

La hierba base actual se conserva en `terrain-grass-muted-generated.png`. Se usa como textura de 32x32 en el terreno abierto y bajo los árboles. El atlas compartido empaqueta estas texturas en cuadrantes de 32x32 para reducir su tamaño de memoria.
