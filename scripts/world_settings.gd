extends RefCounted
## AJUSTES DEL JUEGO. Edita aquí y reinicia Godot / la ejecución del juego.
## Los tiempos son segundos de simulación, salvo AUTOSAVE_INTERVAL (tiempo real).
## Dinero en euros, distancias en casillas, riesgos entre 0.0 y 1.0.
## Tamaño, ciudades iniciales y semilla: solo partidas nuevas.
## Terreno y reglas de clima/abandono se guardan por partida.
## El resto del equilibrio se aplica también al continuar partidas guardadas.

# MAPA Y GENERACIÓN
const INITIAL_SIDE = 1024 # Lado inicial; múltiplo de 1024 y al menos 1024.
const INITIAL_CITY_COUNT = 400 # Si no caben, se generan las posibles y se avisa.
const MIN_CITY_DISTANCE = 100 # Distancia mínima entre centros, también al explorar.
const START_CITY_DISTANCE = 100 # Pareja inicial; al menos MIN_CITY_DISTANCE.
const RANDOM_WORLD_SEED = true # false: todas las partidas nuevas usan WORLD_SEED.
const WORLD_SEED = 42193
const EXPLORATION_CITY_GRID = 7 # 7 → hasta 49 emplazamientos por región nueva.
const EXPLORATION_CITY_JITTER = 20 # Variación ±casillas de cada emplazamiento.
const EXPLORATION_CITY_ATTEMPTS = 24 # Intentos de buscar terreno por emplazamiento.
## Cambiar estos parámetros no modifica el terreno de partidas ya guardadas.
## Umbrales de ruido entre -1 y 1: bajar forest_threshold genera más bosques;
## bajar mountain_threshold genera más montañas. Anchura de río = semianchura.
const TERRAIN = {
	"noise_frequency":0.008, # Más alto: relieves más pequeños y frecuentes.
	"forest_threshold":0.06,
	"mountain_threshold":0.43,
	"rock_threshold":-0.48,
	"river_x_spacing":1400.0,
	"river_y_spacing":2100.0,
	"river_x_half_width":3.5, # 0 desactiva estos ríos.
	"river_y_half_width":2.5
}

# CIUDADES Y CRECIMIENTO
const START_CITY_RADIUS = 3 # Radio en casillas: lado = 2 × radio + 1.
const NEW_CITY_RADIUS = 2
const CITY_STREET_BLOCK_SPACING = 3 # Al menos 3: dos parcelas entre calles paralelas.
const CITY_ACCESS_LENGTH = 3 # Casillas de prolongación exterior de cada salida.
const RESIDENTIAL_ROAD_KIND = 19 # Índices de scripts/catalog.gd: calle residencial.
const AVENUE_ROAD_KIND = 20 # Avenida urbana.
const AVENUE_MIN_CITY_RADIUS = 3
const CITY_BASE_POPULATION = 340
const POPULATION_PER_RADIUS = 700
const CITY_MIN_POPULATION = 160
const CITY_MAX_RADIUS = 5
const CITY_GROWTH_INTERVAL = 60.0
const CITY_BASE_GROWTH = 15 # Habitantes por actualización.
const CITY_GROWTH_PER_TRIP = 3 # Habitantes extra por viaje recibido.
const CITY_MAX_TRIP_GROWTH = 180 # Tope del crecimiento extra por actualización.
const CITY_SHRINK_WITHOUT_TRIPS = 55 # Habitantes perdidos si no hubo viajes.
const CITY_SHRINK_GRACE = 180.0 # Tiempo inicial sin penalización por falta de viajes.

# CÁMARA: píxeles por casilla. 0,5 permite 16× más amplitud que el mínimo anterior.
const MIN_ZOOM = 0.5
const MAX_ZOOM = 96.0

# TRÁFICO E INGRESOS
const STARTING_MONEY = 80000.0
const DEMAND_INTERVAL = 6.0 # Más alto → menos viajes nuevos.
const DEMAND_BASE_CARS = 1
const DEMAND_POPULATION_STEP = 2000 # Cada tantos habitantes añade un coche al lote.
const DEMAND_MAX_CARS = 3 # Máximo por ciudad y lote.
const MAX_VISIBLE_CARS = 350 # Resto en cola; no elimina viajes pendientes.
const CURVE_SPEED_FACTOR = 0.6 # En curvas y giros: 60 % de la velocidad, reducción del 40 %.
const TRIP_BASE_FARE = 20.0
const TRIP_FARE_PER_CELL = 1.8
const TRIP_REFERENCE_SPEED = 4.0 # Casillas/s para comparar tiempo ideal y real.
const TRIP_MIN_TIME_MULTIPLIER = 0.15 # Viajes lentos: fracción mínima del ingreso.
const TRIP_MAX_TIME_MULTIPLIER = 2.5 # Tope para viajes rápidos.

# CONSERVACIÓN Y OBRAS (precios/velocidades/capacidad de cada vía: catalog.gd)
const ROAD_PASSIVE_WEAR = 0.0015 # Puntos de conservación por segundo abierta.
const ROAD_TRAFFIC_WEAR = 0.007 # Puntos por coche y segundo sobre la casilla.
const ROAD_MIN_HEALTH = 5.0
const UPGRADE_COST_RATIO = 0.75 # Fracción del precio de la nueva vía.
const REPAIR_COST_RATIO = 0.25 # Fracción del precio de construcción.
const REPAIR_BASE_TIME = 4.0
const REPAIR_TIME_PER_DAMAGE = 0.06 # Segundos extra por punto de daño.
const DEMOLITION_COST_RATIO = 0.25
const DEMOLITION_TIME = 5.0
const LOGGING_COST = 20.0
const LOGGING_TIME = 3.0
const SIGNAL_NS_GREEN = 10.0 # Duraciones iniciales; después configurables en juego.
const SIGNAL_EW_GREEN = 10.0

# ACCIDENTES (los riesgos se suman, con máximo del 100 %)
const ACCIDENT_INTERVAL = 30.0
const ACCIDENT_COST = 100.0
const ACCIDENT_STOP = 15.0
const FIRE_ACCIDENT_RISK = 0.30
const SNOW_ACCIDENT_RISK = 0.30
const DAMAGED_ACCIDENT_RISK = 0.05 # Conservación inferior al 75 %.
const VERY_DAMAGED_ACCIDENT_RISK = 0.15 # Inferior al 40 %.
const EXTREME_DAMAGE_ACCIDENT_RISK = 0.30 # Inferior al 15 %.

# CLIMA Y ABANDONO: valores iniciales de las reglas guardadas con cada partida.
const WEATHER_ENABLED = true
const WEATHER_INTERVAL = 180.0
const WEATHER_SNOW_CHANCE = 0.5 # 0 solo incendios; 1 solo nieve.
const SNOW_RADIUS = 6
const SNOW_DURATION = 120.0
const FIRE_DURATION = 60.0
const FIRE_SPREAD_INTERVAL = 5.0
const ABANDONMENT_ENABLED = true
const UNUSED_ROAD_DELAY = 600.0 # Tiempo sin coches antes de empezar a desaparecer.
const UNUSED_ROAD_FADE_TIME = 300.0 # Duración de la desaparición gradual.

# GUARDADO
const AUTOSAVE_ENABLED = true
const AUTOSAVE_INTERVAL = 60.0 # Segundos reales; no cambia con la velocidad.

static func incident_rules() -> Dictionary:
	return {"weather_enabled":WEATHER_ENABLED,"abandon_enabled":ABANDONMENT_ENABLED,
		"weather_interval":WEATHER_INTERVAL,"snow_chance":WEATHER_SNOW_CHANCE,
		"snow_radius":SNOW_RADIUS,"snow_duration":SNOW_DURATION,"fire_duration":FIRE_DURATION,
		"fire_spread":FIRE_SPREAD_INTERVAL,"unused_start":UNUSED_ROAD_DELAY,"unused_fade":UNUSED_ROAD_FADE_TIME}

static func validate() -> void:
	assert(MIN_ZOOM>0 and MIN_ZOOM<=MAX_ZOOM,"Revisa los límites del zoom")
	assert(INITIAL_SIDE>=1024 and INITIAL_SIDE%1024==0,"INITIAL_SIDE: múltiplo de 1024 y al menos 1024")
	assert(INITIAL_CITY_COUNT>=2 and MIN_CITY_DISTANCE>0 and START_CITY_DISTANCE>=MIN_CITY_DISTANCE,"Revisa cantidad y separación de ciudades")
	assert(EXPLORATION_CITY_GRID>0 and EXPLORATION_CITY_JITTER>=0 and EXPLORATION_CITY_ATTEMPTS>0,"Revisa parámetros EXPLORATION_CITY_…")
	assert(START_CITY_RADIUS>=1 and NEW_CITY_RADIUS>=1 and CITY_MAX_RADIUS>=maxi(START_CITY_RADIUS,NEW_CITY_RADIUS),"Revisa radios de ciudades")
	assert(CITY_STREET_BLOCK_SPACING>=3 and CITY_ACCESS_LENGTH>=1 and AVENUE_MIN_CITY_RADIUS>=1 and RESIDENTIAL_ROAD_KIND in range(24) and AVENUE_ROAD_KIND in range(24),"Revisa accesos e índices de vías urbanas")
	assert(POPULATION_PER_RADIUS>0 and CITY_MIN_POPULATION>0 and CITY_GROWTH_INTERVAL>0,"Revisa población e intervalo de crecimiento")
	assert(DEMAND_INTERVAL>0 and DEMAND_POPULATION_STEP>0 and DEMAND_MAX_CARS>0 and DEMAND_BASE_CARS>=0 and MAX_VISIBLE_CARS>0,"Revisa parámetros de tráfico")
	assert(CURVE_SPEED_FACTOR>0 and CURVE_SPEED_FACTOR<=1,"CURVE_SPEED_FACTOR debe ser mayor que 0 y como máximo 1")
	assert(TRIP_REFERENCE_SPEED>0 and TRIP_MIN_TIME_MULTIPLIER>=0 and TRIP_MAX_TIME_MULTIPLIER>=TRIP_MIN_TIME_MULTIPLIER,"Revisa ingresos por tiempo de viaje")
	assert(ROAD_MIN_HEALTH>0 and ROAD_MIN_HEALTH<=100 and ROAD_PASSIVE_WEAR>=0 and ROAD_TRAFFIC_WEAR>=0,"Revisa conservación")
	assert(STARTING_MONEY>=0 and TRIP_BASE_FARE>=0 and TRIP_FARE_PER_CELL>=0,"Los importes no pueden ser negativos")
	for value in [UPGRADE_COST_RATIO,REPAIR_COST_RATIO,REPAIR_BASE_TIME,REPAIR_TIME_PER_DAMAGE,DEMOLITION_COST_RATIO,DEMOLITION_TIME,LOGGING_COST,LOGGING_TIME,ACCIDENT_COST,ACCIDENT_STOP,CITY_SHRINK_GRACE,UNUSED_ROAD_DELAY]:
		assert(value>=0,"Costes y tiempos no pueden ser negativos")
	for value in [ACCIDENT_INTERVAL,WEATHER_INTERVAL,SNOW_DURATION,FIRE_DURATION,FIRE_SPREAD_INTERVAL,UNUSED_ROAD_FADE_TIME,AUTOSAVE_INTERVAL]:
		assert(value>0,"Los intervalos y duraciones deben ser mayores que cero")
	for value in [FIRE_ACCIDENT_RISK,SNOW_ACCIDENT_RISK,DAMAGED_ACCIDENT_RISK,VERY_DAMAGED_ACCIDENT_RISK,EXTREME_DAMAGE_ACCIDENT_RISK,WEATHER_SNOW_CHANCE]:
		assert(value>=0 and value<=1,"Los riesgos/probabilidades deben estar entre 0 y 1")
	assert(SNOW_RADIUS>=0 and SIGNAL_NS_GREEN>=1 and SIGNAL_NS_GREEN<=120 and SIGNAL_EW_GREEN>=1 and SIGNAL_EW_GREEN<=120,"Revisa nieve y tiempos de semáforo")
	assert(TERRAIN.noise_frequency>0 and TERRAIN.river_x_spacing>0 and TERRAIN.river_y_spacing>0 and TERRAIN.river_x_half_width>=0 and TERRAIN.river_y_half_width>=0,"Revisa frecuencia y ríos del terreno")
	assert(TERRAIN.rock_threshold<TERRAIN.forest_threshold and TERRAIN.forest_threshold<TERRAIN.mountain_threshold,"Orden de umbrales: rocas < bosques < montañas")
	assert(TERRAIN.rock_threshold>=-1 and TERRAIN.mountain_threshold<=1,"Los umbrales de terreno deben estar entre -1 y 1")
