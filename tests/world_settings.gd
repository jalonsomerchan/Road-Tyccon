extends SceneTree
const S = preload("res://scripts/world_settings.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	S.validate()
	var g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g);g.set_process(false)
	assert(g.money==S.STARTING_MONEY and g.accounts.opening==S.STARTING_MONEY)
	assert(g.world_seed==S.WORLD_SEED and g.cities.size()==S.INITIAL_CITY_COUNT)
	assert(g.cities[0].radius==S.START_CITY_RADIUS)
	assert(g.cities[0].pop==(S.START_CITY_RADIUS-1)*S.POPULATION_PER_RADIUS+S.CITY_BASE_POPULATION)
	var pop=g.cities[0].pop
	g.cities[0].recent=4
	g.grow_cities()
	assert(g.cities[0].pop==maxi(S.CITY_MIN_POPULATION,pop+S.CITY_BASE_GROWTH+mini(4*S.CITY_GROWTH_PER_TRIP,S.CITY_MAX_TRIP_GROWTH)))
	for c in g.cities:
		for a in c.accesses:
			assert(a.end-a.gate==a.dir*(S.CITY_ACCESS_LENGTH-1))
	assert(g.incidents.rules==S.incident_rules())
	g.incidents.rules.weather_interval=987.0
	var weather=g.incidents.snapshot()
	g.incidents.reset()
	assert(g.incidents.rules==S.incident_rules(),"A new world resets rules to the configured defaults")
	g.incidents.restore(weather)
	assert(g.incidents.rules.weather_interval==987.0,"Saved weather rules take precedence")
	g.incidents.reset()
	assert(g.terrain.parameters==S.TERRAIN)
	for i in 100:
		var p=Vector2i(i*157,i*149)
		assert(g.terrain.get_cell(p)==g.terrain.sample_cell(p))
	var saved=g.terrain.snapshot()
	var custom=saved.duplicate(true)
	custom.parameters.noise_frequency=.024
	custom.parameters.river_x_half_width=0.0
	g.terrain.restore(custom)
	assert(is_equal_approx(g.terrain.noise.frequency,.024) and g.terrain.parameters.river_x_half_width==0)
	assert(g.terrain.snapshot().parameters==custom.parameters)
	g.terrain.restore({"seed":S.WORLD_SEED})
	assert(g.terrain.parameters==g.World.LEGACY_TERRAIN,"Old maps retain their historical terrain settings")
	g.terrain.restore(saved)
	g.traffic.reset();g.cars.clear()
	g.cities[0].unlocked=[1]
	g.cities[0].pop=S.DEMAND_POPULATION_STEP*2
	g.cities[0].profile=0
	g.elapsed=120
	g.spawn_trips()
	assert(g.cars.size()+g.traffic.queued==int(mini(S.DEMAND_MAX_CARS,S.DEMAND_BASE_CARS+2)*1.8))
	var money=g.money
	g.traffic.complete({"ideal":10.0,"age":10.0,"dest":1})
	var expected=(S.TRIP_BASE_FARE+10*S.TRIP_REFERENCE_SPEED*S.TRIP_FARE_PER_CELL)*clampf(1.0,S.TRIP_MIN_TIME_MULTIPLIER,S.TRIP_MAX_TIME_MULTIPLIER)
	assert(is_equal_approx(g.money-money,expected))
	g.terrain.fill(0)
	var p=Vector2i(100,100)
	g.roads[p]=g.city_road(0,true)
	g.roads[p].hp=10
	g.incidents.fire[p]=100;g.incidents.snow[p]=100
	assert(is_equal_approx(g.incidents.risk(p),minf(1,S.EXTREME_DAMAGE_ACCIDENT_RISK+S.FIRE_ACCIDENT_RISK+S.SNOW_ACCIDENT_RISK)))
	assert(g.incidents.ACCIDENT_INTERVAL==S.ACCIDENT_INTERVAL and g.incidents.ACCIDENT_COST==S.ACCIDENT_COST and g.incidents.ACCIDENT_STOP==S.ACCIDENT_STOP)
	g.money=1000000;money=g.money
	g.maintenance.demolition(p)
	assert(is_equal_approx(money-g.money,g.Catalog.ROADS[0].cost*S.DEMOLITION_COST_RATIO))
	assert(g.maintenance.jobs[p].left==S.DEMOLITION_TIME)
	g.maintenance.update(S.DEMOLITION_TIME+.1)
	assert(not g.roads.has(p))
	g.terrain.set_cell(p,2);money=g.money
	g.maintenance.logging(p)
	assert(g.money==money-S.LOGGING_COST and g.maintenance.jobs[p].left==S.LOGGING_TIME)
	g.maintenance.update(S.LOGGING_TIME+.1)
	assert(g.ground(p)==0)
	g.roads[p]=g.city_road(0,true);g.cursor=p
	g.install_signal()
	assert(g.incidents.signals[p].ns==S.SIGNAL_NS_GREEN and g.incidents.signals[p].ew==S.SIGNAL_EW_GREEN)
	if not S.RANDOM_WORLD_SEED:
		g.reset_armed=true;g.new_game()
		assert(g.world_seed==S.WORLD_SEED and g.money==S.STARTING_MONEY)
	print("PASS: settings drive generation, access lengths, population, money, traffic demand, fares, maintenance, risks, signals and saved terrain/weather compatibility")
	g.free();quit()
