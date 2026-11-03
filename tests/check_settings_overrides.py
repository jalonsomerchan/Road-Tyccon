"""Prueba parámetros alternativos sin modificar el proyecto ni sus guardados.

Uso: python3 tests/check_settings_overrides.py /ruta/al/ejecutable/Godot
"""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parents[1]
overrides = {
    "INITIAL_SIDE": "1024", "INITIAL_CITY_COUNT": "12",
    "MIN_CITY_DISTANCE": "80", "START_CITY_DISTANCE": "100",
    "RANDOM_WORLD_SEED": "false", "WORLD_SEED": "1234",
    "START_CITY_RADIUS": "3", "NEW_CITY_RADIUS": "2", "CITY_ACCESS_LENGTH": "5",
    "STARTING_MONEY": "123456.0", "CITY_BASE_POPULATION": "520",
    "POPULATION_PER_RADIUS": "900", "DEMAND_INTERVAL": "11.0",
    "DEMAND_BASE_CARS": "2", "DEMAND_POPULATION_STEP": "1000", "DEMAND_MAX_CARS": "5",
    "MAX_VISIBLE_CARS": "32", "CURVE_SPEED_FACTOR": "0.45", "TRIP_BASE_FARE": "55.0", "TRIP_FARE_PER_CELL": "3.1",
    "TRIP_REFERENCE_SPEED": "2.5", "TRIP_MIN_TIME_MULTIPLIER": "0.4",
    "TRIP_MAX_TIME_MULTIPLIER": "1.8", "DEMOLITION_COST_RATIO": "0.4",
    "DEMOLITION_TIME": "1.25", "LOGGING_COST": "44.0", "LOGGING_TIME": "0.75",
    "ACCIDENT_INTERVAL": "17.0", "ACCIDENT_COST": "222.0", "ACCIDENT_STOP": "8.0",
    "FIRE_ACCIDENT_RISK": "0.12", "SNOW_ACCIDENT_RISK": "0.25",
    "EXTREME_DAMAGE_ACCIDENT_RISK": "0.4", "SIGNAL_NS_GREEN": "7.0",
    "SIGNAL_EW_GREEN": "13.0", "WEATHER_ENABLED": "false", "WEATHER_INTERVAL": "333.0",
    "SNOW_RADIUS": "3", "SNOW_DURATION": "90.0", "FIRE_DURATION": "45.0",
    "FIRE_SPREAD_INTERVAL": "7.0", "UNUSED_ROAD_DELAY": "120.0",
    "UNUSED_ROAD_FADE_TIME": "40.0", "AUTOSAVE_ENABLED": "false",
}
with tempfile.TemporaryDirectory(prefix="road-settings-") as directory:
    target = Path(directory)
    for folder in ["scripts", "scenes"]:
        shutil.copytree(project / folder, target / folder)
    for folder in ["assets", ".godot"]:
        if (project / folder).exists():
            (target / folder).symlink_to(project / folder, target_is_directory=True)
    shutil.copy2(project / "project.godot", target / "project.godot")
    (target / "tests").mkdir()
    shutil.copy2(project / "tests/world_settings.gd", target / "tests/world_settings.gd")
    settings = target / "scripts/world_settings.gd"
    text = settings.read_text()
    for key, value in overrides.items():
        text, count = re.subn(rf"(?m)^(const {key} = )[^\n]+", rf"\g<1>{value}", text)
        assert count == 1, key
    text = text.replace('"noise_frequency":0.008', '"noise_frequency":0.018')
    text = text.replace('"river_x_half_width":3.5', '"river_x_half_width":0.0')
    text = text.replace('"forest_threshold":0.06', '"forest_threshold":-0.05')
    settings.write_text(text)
    result = subprocess.run(
        [sys.argv[1] if len(sys.argv) > 1 else "godot", "--headless", "--path", str(target),
         "--script", "tests/world_settings.gd", "--", "--test-mode"],
        capture_output=True, text=True, timeout=35,
    )
    output = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR" in output or "PASS:" not in output:
        raise SystemExit(output)
    print("PASS: alternative configuration in an isolated project\n" + result.stdout)
