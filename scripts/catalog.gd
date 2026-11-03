extends RefCounted
## Valores iniciales de equilibrio: coste por casilla, carriles, velocidad, capacidad y obra. Todas ocupan una casilla.
const ROADS = [
	{"name":"Camino de tierra", "w":1, "lanes":1, "speed":1.7, "cap":2, "cost":35, "time":1.5, "color":"947650"},
	{"name":"Camino de grava", "w":1, "lanes":1, "speed":2.2, "cap":3, "cost":55, "time":2.0, "color":"a6a08b"},
	{"name":"Camino de cemento", "w":1, "lanes":1, "speed":2.8, "cap":4, "cost":85, "time":2.5, "color":"b4b5a6"},
	{"name":"Carretera local", "w":1, "lanes":2, "speed":3.2, "cap":5, "cost":110, "time":3.0, "color":"646e70"},
	{"name":"Carretera secundaria", "w":1, "lanes":2, "speed":4.0, "cap":6, "cost":150, "time":3.5, "color":"58646b"},
	{"name":"Carretera principal", "w":1, "lanes":2, "speed":4.8, "cap":10, "cost":320, "time":5.0, "color":"56616a"},
	{"name":"Carretera rápida", "w":1, "lanes":2, "speed":5.8, "cap":14, "cost":460, "time":6.0, "color":"485660"},
	{"name":"Autovía", "w":1, "lanes":4, "speed":6.8, "cap":20, "cost":650, "time":8.0, "color":"46535c"},
	{"name":"Autopista", "w":1, "lanes":6, "speed":8.0, "cap":30, "cost":1000, "time":10.0, "color":"3e4c56"},
	{"name":"Autopista de alta capacidad", "w":1, "lanes":8, "speed":8.5, "cap":42, "cost":1400, "time":12.0, "color":"374752"},
	{"name":"Puente de madera", "w":1, "lanes":1, "speed":2.0, "cap":3, "cost":170, "time":5.0, "color":"ac8051", "bridge":true},
	{"name":"Puente de piedra", "w":1, "lanes":2, "speed":3.5, "cap":6, "cost":280, "time":7.0, "color":"b5ac94", "bridge":true},
	{"name":"Puente de hormigón", "w":1, "lanes":2, "speed":5.0, "cap":12, "cost":700, "time":9.0, "color":"b2bdb8", "bridge":true},
	{"name":"Puente de acero", "w":1, "lanes":4, "speed":6.5, "cap":22, "cost":1050, "time":11.0, "color":"82a4a3", "bridge":true},
	{"name":"Puente atirantado", "w":1, "lanes":6, "speed":8.0, "cap":32, "cost":1800, "time":14.0, "color":"c4c9b7", "bridge":true},
	{"name":"Puente colgante", "w":1, "lanes":6, "speed":8.5, "cap":42, "cost":2400, "time":16.0, "color":"c18b69", "bridge":true},
	{"name":"Camino forestal", "w":1, "lanes":1, "speed":1.8, "cap":3, "cost":42, "time":1.6, "color":"6f7350"},
	{"name":"Camino agrícola", "w":1, "lanes":1, "speed":1.9, "cap":3, "cost":48, "time":1.8, "color":"ad935d"},
	{"name":"Camino adoquinado", "w":1, "lanes":1, "speed":2.5, "cap":4, "cost":75, "time":2.5, "color":"9d9686"},
	{"name":"Calle residencial", "w":1, "lanes":2, "speed":2.8, "cap":7, "cost":125, "time":3.0, "color":"777b77"},
	{"name":"Avenida urbana", "w":1, "lanes":4, "speed":3.8, "cap":16, "cost":380, "time":5.0, "color":"5d6864"},
	{"name":"Carretera comarcal", "w":1, "lanes":2, "speed":4.3, "cap":8, "cost":210, "time":4.0, "color":"526474"},
	{"name":"Circunvalación", "w":1, "lanes":4, "speed":6.2, "cap":24, "cost":780, "time":8.0, "color":"455b61"},
	{"name":"Autopista exprés", "w":1, "lanes":8, "speed":9.0, "cap":48, "cost":1650, "time":14.0, "color":"354a59"}
]
