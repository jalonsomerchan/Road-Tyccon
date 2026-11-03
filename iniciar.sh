
#!/bin/bash

GAME_DIR="$HOME/Games/MiJuego"

PY_URL="https://raw.githubusercontent.com/jalonsomerchan/Road-Tyccon/main/launcher.py"

mkdir -p "$GAME_DIR"
cd "$GAME_DIR" || exit 1

# Guardar logs
exec >> "$GAME_DIR/launcher.log" 2>&1

echo ""
echo "=================================="
echo "Inicio: $(date)"
echo "=================================="

# Descargar la última versión del launcher
echo "Buscando actualización del launcher..."

if curl -fLsS \
    --connect-timeout 5 \
    --max-time 20 \
    "$PY_URL" \
    -o launcher.py.tmp; then

    # Comprobar que el Python descargado es válido
    if /usr/bin/python3 -m py_compile launcher.py.tmp; then
        mv -f launcher.py.tmp launcher.py
        echo "Launcher actualizado correctamente."
    else
        echo "El launcher descargado contiene errores."
        rm -f launcher.py.tmp
    fi
else
    echo "No se pudo descargar el launcher."
    rm -f launcher.py.tmp
fi

# Comprobar que existe una versión local
if [ ! -f launcher.py ]; then
    echo "ERROR: No existe launcher.py"
    exit 1
fi

# Ejecutar el actualizador del juego
echo "Ejecutando launcher..."
exec /usr/bin/python3 launcher.py
