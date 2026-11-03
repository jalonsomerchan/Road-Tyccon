extends RefCounted
## Libro de caja: totales completos y movimientos recientes, sin depender de la interfaz.
const LABELS = {"trips":"Viajes", "construction":"Construcción", "upgrades":"Mejoras", "repairs":"Reparaciones", "demolition":"Demoliciones", "logging":"Tala de árboles", "accidents":"Accidentes", "legacy":"Gastos anteriores sin desglose", "cheats":"Trucos", "contracts":"Contratos", "upkeep":"Conservación", "services":"Servicios", "refunds":"Devoluciones"}
const Settings = preload("res://scripts/world_settings.gd")
var opening = Settings.STARTING_MONEY
var totals: Dictionary = {}
var entries: Array = []
var sequence = 0
var periods: Dictionary = {}

func reset(balance: float = Settings.STARTING_MONEY) -> void:
	opening = balance
	totals.clear()
	entries.clear()
	periods.clear()
	sequence = 0

func record(amount: float, category: String, description: String, at: float, legacy: bool = false) -> void:
	if is_zero_approx(amount): return
	sequence += 1
	totals[category] = float(totals.get(category,0.0)) + amount
	entries.append({"id":sequence,"amount":amount,"category":category,"description":description,"at":at,"legacy":legacy})
	if entries.size() > 1000: entries.pop_front()
	if not legacy:
		var minute = int(at / 60)
		if not periods.has(minute): periods[minute] = {"income":0.0,"expenses":0.0}
		if amount > 0: periods[minute].income += amount
		else: periods[minute].expenses -= amount
		if periods.size() > 128: periods.erase(periods.keys()[0])

func income() -> float:
	var total = 0.0
	for category in totals:
		if totals[category] > 0: total += totals[category]
	return total

func expenses() -> float:
	var total = 0.0
	for category in totals:
		if totals[category] < 0: total -= totals[category]
	return total

func recent(filter_mode: int = 0) -> Array:
	var result: Array = []
	for i in range(entries.size()-1,-1,-1):
		var entry = entries[i]
		if filter_mode == 1 and entry.amount <= 0: continue
		if filter_mode == 2 and entry.amount >= 0: continue
		result.append(entry)
	return result

func legacy_balance(earned: float, losses: float, balance: float, at: float) -> void:
	reset(80000.0)
	record(earned,"trips","Ingresos anteriores",at,true)
	record(-losses,"accidents","Accidentes anteriores",at,true)
	var spending = opening + earned - losses - balance
	record(-spending,"legacy","Partida anterior: sin desglose por concepto",at,true)

func snapshot() -> Dictionary:
	return {"opening":opening,"totals":totals,"entries":entries,"periods":periods,"sequence":sequence}

func restore(data: Dictionary) -> void:
	reset(data.get("opening",80000.0))
	totals = data.get("totals",{})
	entries = data.get("entries",[])
	periods = data.get("periods",{})
	sequence = data.get("sequence",entries.size())

static func format_money(amount: float) -> String:
	return ("%.2f" % amount).replace(".",",") + " €"
