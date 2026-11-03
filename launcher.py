
#!/usr/bin/env python3

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path

# CAMBIAR POR TU USUARIO Y REPOSITORIO
REPO = "jalonsomerchan/Road-Tyccon"

BASE = Path.home() / "Games" / "MiJuego"
GAME = BASE / "juego"
OLD = BASE / "juego-anterior"
VERSION = BASE / "version.txt"
EXECUTABLE = "MiJuego.x86_64"

API = f"https://api.github.com/repos/{REPO}/releases/latest"


def download(url, path):
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Godot-SteamDeck-Updater"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        with open(path, "wb") as file:
            shutil.copyfileobj(response, file)


def update():
    BASE.mkdir(parents=True, exist_ok=True)

    request = urllib.request.Request(
        API,
        headers={
            "User-Agent": "Godot-SteamDeck-Updater",
            "Accept": "application/vnd.github+json"
        }
    )

    with urllib.request.urlopen(request, timeout=15) as response:
        release = json.load(response)

    latest = release["tag_name"]
    installed = VERSION.read_text().strip() if VERSION.exists() else ""

    if latest == installed and (GAME / EXECUTABLE).is_file():
        print("Juego actualizado.")
        return

    assets = {
        asset["name"]: asset["browser_download_url"]
        for asset in release["assets"]
    }

    print(f"Instalando {latest}...", flush=True)

    with tempfile.TemporaryDirectory(dir=BASE) as tmp:
        tmp = Path(tmp)
        archive = tmp / "steamdeck.zip"
        checksum = tmp / "steamdeck.zip.sha256"
        staging = tmp / "nuevo"

        download(assets["steamdeck.zip"], archive)
        download(assets["steamdeck.zip.sha256"], checksum)

        expected = checksum.read_text().split()[0].lower()
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()

        if expected != actual:
            raise RuntimeError("Verificación SHA-256 fallida")

        staging.mkdir()

        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                target = (staging / member.filename).resolve()

                if not target.is_relative_to(staging.resolve()):
                    raise RuntimeError("Ruta insegura en ZIP")

                mode = (member.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    raise RuntimeError("Enlace simbólico no permitido")

            z.extractall(staging)

        binary = staging / EXECUTABLE

        if not binary.is_file():
            raise RuntimeError("No se encuentra el ejecutable")

        binary.chmod(binary.stat().st_mode | 0o111)

        # Mantener la versión anterior como respaldo.
        if OLD.exists():
            shutil.rmtree(OLD)

        if GAME.exists():
            GAME.rename(OLD)

        try:
            staging.rename(GAME)
            VERSION.write_text(latest)
        except Exception:
            if GAME.exists():
                shutil.rmtree(GAME)
            if OLD.exists():
                OLD.rename(GAME)
            raise

        print("Actualización instalada.", flush=True)


def main():
    try:
        update()
    except Exception as error:
        print(f"No se pudo actualizar: {error}", flush=True)

    binary = GAME / EXECUTABLE

    if not binary.is_file():
        print("No hay una versión instalada.")
        return 1

    os.chdir(GAME)
    return subprocess.call([str(binary)])


if __name__ == "__main__":
    raise SystemExit(main())
