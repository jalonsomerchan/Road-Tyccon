# Entre Ciudades

Tycoon cenital pixel art para Godot 4.7.2, con teclado y mando. Abre `project.godot` y ejecuta con F5.

## Objetivos, progresión y gestión de la red

La pantalla inicial permite elegir con **X** (o su botón) entre **Progresión**, **Libre** y tres escenarios. Progresión empieza con tierra, carretera local, puente de madera y caminos forestal/agrícola. Los contratos dan dinero y reputación: los niveles de **20, 80 y 180** puntos desbloquean sucesivamente vías secundarias, autovías y grandes autopistas. Libre y los escenarios tienen el catálogo completo. Las partidas v2 anteriores se cargan en Libre, conservando dinero, carreteras, vehículos y contabilidad.

**Objetivos (K)** muestra tres contratos simultáneos: conectar ciudades, completar viajes y completar viajes con una demora de hasta diez segundos frente al tiempo de referencia. Se cobra cada hito una sola vez; después aparece uno mayor. Conectar una ciudad y completar contratos genera una celebración. Las intervenciones realizadas con al menos cinco viajes de referencia se comparan después de 60 segundos y cinco nuevos viajes; se muestran la demora y la cola antes/después. La comparación refleja el tráfico observado, que también puede cambiar con la demanda.

Cada ciudad tiene un perfil persistente. Las dos iniciales son residencial e industrial; las demás reciben su perfil de forma determinista:

| Perfil | Demanda y recompensa |
| --- | --- |
| Residencial | Demanda ×1,8 en las fases 2, 3, 7 y 8 del ciclo de diez minutos; ×0,8 fuera de ellas. |
| Industrial | Demanda ×1,25 en las fases 2–8 y ×0,6 fuera de ellas; vehículos ×0,8 de velocidad y ×1,4 de tarifa. |
| Turística | Demanda ×1,6 en las fases 0, 1, 8 y 9; ×0,7 el resto; tarifa ×1,25. |
| Agrícola | Demanda ×2 durante la cosecha (una fase de cinco minutos de cada cuatro); ×0,7 el resto; tarifa ×1,2. |

Los multiplicadores se aplican a la demanda por población, conservando las fracciones para futuras salidas. La primera conexión garantiza una salida inicial. Los destinos se ponderan por población y complementariedad entre perfiles. El límite de vehículos visibles sigue siendo 350; la demanda adicional permanece en cola. Una ciudad que aún no ha entrado en la red no pierde habitantes por falta de viajes; al conectarse empieza su plazo de gracia.

**Red y servicios**, dentro del menú, tiene tres pestañas accesibles con ratón, flechas y mando:

- **Tramos y mantenimiento:** elige desde el cursor hasta los cruces (hasta 2.048 casillas), repara el tramo o contrata mantenimiento automático por debajo del 35, 55 o 75 %. La reparación con cierre cuesta el porcentaje configurado y devuelve la vía a su estado de apertura anterior. La parcial cuesta ×1,5 y tarda el doble: mantiene el paso con capacidad al 50 % y velocidad al 55 %. Los trabajos y su progreso se guardan. Las vías municipales sin modificar quedan fuera del mantenimiento automático.
- **Tráfico y emergencias:** capas de congestión, conservación y rentabilidad estimada; diagnóstico con botón para ir al punto; selección de vehículos con ruta, destino y causa de parada. **C** o **Ctrl+clic** abre la inspección; **L** alterna capas. La previsión muestra el próximo fenómeno y su cuenta atrás. Bomberos (250 €) y quitanieves (180 €) despejan efectos en un radio de doce casillas alrededor del cursor; los bomberos eliminan también las fuentes de propagación extinguidas. Los eventos priorizan las vías del jugador.
- **Economía:** conservación por minuto, ingresos recientes de viajes, caja prevista a cinco minutos y comparación paginada de conexiones. Las vías del jugador cuestan el **0,08 % de su precio de construcción por minuto simulado**; las calles municipales sin modificar no generan ese gasto. Una ruta muestra el coste completo de sus vías, por lo que sus márgenes sirven para comparar y no deben sumarse cuando comparten tramos. La capa de rentabilidad distribuye el ingreso de cada viaje por sus casillas recorridas. La previsión excluye contratos, devoluciones, nuevas obras, accidentes y reparaciones futuras.

Una vía marcada como **reserva** no desaparece por desuso y paga un 35 % adicional de conservación. **Construir desvío temporal** marca el siguiente tramo para retirarse a los cinco minutos; espera hasta que esté vacío y sin obras. **Ctrl+Z** devuelve el importe de la última construcción durante los primeros 60 segundos, siempre que no haya sido utilizada ni modificada; también revierte rotondas y restaura sus vías anteriores. Los cierres y mejoras normales conservan sus controles habituales.

**Escenarios** ofrece semillas fijas y resultados locales:

| Escenario | Duración simulada | Presupuesto | Objetivo |
| --- | --- | --- | --- |
| Pueblos con presupuesto | 15 min | 12.000 € | 120 viajes |
| Invierno en la región | 20 min | 30.000 € | 180 viajes; nevadas cada 90 s |
| La gran conexión | 30 min | 45.000 € | 6 ciudades conectadas |

Además del objetivo, hay que terminar con caja no negativa. Al vencer el plazo se pausa la simulación y se presenta el resultado. La puntuación considera viajes, conexiones, caja, accidentes y demora. El mejor resultado por escenario se guarda aparte de la partida; usar trucos desactiva el récord de esa sesión. Se puede repetir un reto o continuar la región en Libre. Preparar un escenario desde el menú muestra su presupuesto y objetivo y exige pulsar **Iniciar el reto seleccionado** antes de reemplazar la sesión.

Los nuevos estados se incluyen en el guardado v2 con valores por defecto para partidas anteriores. Los contratos, trabajos y resultados se conservan al cargar. El historial de muestras se limita a 256 viajes y las comparaciones a seis intervenciones.

Verificación de las nuevas mecánicas y regresiones en un proyecto aislado:

```sh
python3 tools/run_checks.py /Applications/Godot.app/Contents/MacOS/Godot
python3 tests/check_settings_overrides.py /Applications/Godot.app/Contents/MacOS/Godot
# Capturas y navegación sobre una sesión gráfica de prueba:
godot --path . --script tests/capture_gameplay.gd -- --test-mode --title-screen
```

La batería histórica usa una región de 2.048 casillas para sus 400 ciudades y ejecuta también las nuevas mecánicas con la configuración real del proyecto. El ajuste local actual de 1.024 casillas no permite albergar las 400 ciudades solicitadas con 100 casillas de separación; el generador conserva su aviso y crea las que caben, sin cambiar esos ajustes del usuario.

## Pantalla de inicio

Al abrir el juego aparecen **Nueva partida**, **Cargar partida** y **Salir**. La simulación no empieza ni genera la región hasta elegir Nueva o Cargar. Cargar está desactivado si no hay guardado; los archivos incompatibles muestran un mensaje y mantienen la pantalla inicial.

Flechas / WASD, cruceta o stick eligen y Enter / A confirma; también funciona el ratón. Si ya hay guardado, Nueva partida pide confirmación con ← / → y Enter / A, o B / Esc para cancelar. La nueva región reemplaza el guardado al guardar, autoguardar o cerrar esa sesión. Cerrar el juego desde el inicio conserva el archivo existente.

## Carreteras

Todas las carreteras y puentes ocupan **una única casilla**, con independencia de sus carriles. Las vías de un carril se dibujan más finas; las de dos o más llevan un sprite opaco de pavimento que llena la casilla. Los carriles influyen en la capacidad, junto con la velocidad y el estado de la vía.

Hay **24 tipos**: tierra, grava, cemento, carretera local, secundaria, principal, rápida, autovía, autopista, autopista de alta capacidad; puentes de madera, piedra, hormigón, acero, atirantado y colgante; caminos forestal, agrícola y adoquinado, calle residencial, avenida urbana, carretera comarcal, circunvalación y autopista exprés.

Cada tipo tiene cuatro sprites propios: **recta, curva, cruce en T y cruce de cuatro brazos**. El juego los elige y gira según las conexiones. Son **96 sprites de vías**, regenerados con ImageGen y registrados para que rectas, curvas y cruces compartan exactamente los píxeles de sus conexiones. El juego utiliza `assets/sprites/roads-v5/`; las láminas originales, especificaciones de prompts y QC están en `assets/source/visual-refresh/`. Las generaciones anteriores se conservan como fuentes.

Construir, reparar y mejorar lleva tiempo. Cierra antes de reparar o mejorar y vuelve a abrir después. Las obras se marcan en ámbar y los cierres con cruces, barreras y luces rojas. Los ríos requieren puentes; las montañas y los roquedos obligan a rodearlos. Los costes y tiempos iniciales se pueden ajustar en `scripts/catalog.gd`.

Las **curvas y los giros reducen la velocidad al 60 %** (un 40 % menos), ajustable mediante `CURVE_SPEED_FACTOR` en `scripts/world_settings.gd`. La penalización depende de la maniobra real: girar en un cruce ralentiza al coche, mientras que atravesarlo en línea recta mantiene su velocidad. El cálculo de rutas considera la dirección de llegada y ese tiempo extra, de modo que favorece los trazados más rectos cuando resultan más rápidos. La reducción se combina con el estado de la vía, los vehículos industriales y las obras parciales. La dirección se conserva al recalcular rutas y al guardar/cargar, y la inspección de vehículos indica cuándo están tomando una curva.

## Región y ciudades

El mapa empieza con **2.048 × 2.048 casillas** y se amplía al explorar, sin un borde de juego fijo. Las regiones descubiertas son de 1.024 × 1.024; el terreno se materializa bajo demanda en bloques de 32 × 32 con una caché limitada. Se puede avanzar en cualquier dirección, incluidas coordenadas negativas. El guardado conserva las regiones descubiertas, sus ciudades, la semilla y las modificaciones; las zonas visitadas no cambian ni duplican ciudades al regresar.

Las dos primeras ciudades, Valverde y Los Olmos, empiezan alineadas a 100 casillas de distancia, con sus accesos enfrentados y terreno transitable entre ellas para facilitar la primera conexión. La región empieza con las 400 ciudades ya generadas y repartidas por la región inicial. Todas las ciudades, incluida la pareja inicial, mantienen una distancia mínima de 100 casillas entre sí. Hay bosques, praderas, ríos, montañas y roquedos. Las zonas nuevas generan también ciudades al descubrirlas, con hasta 49 emplazamientos por región y sin un límite total de ciudades. Su aparición depende de la exploración, no del tiempo. Las ciudades nuevas respetan la separación y evitan las carreteras existentes. Las ciudades crecen con el tiempo y los viajes recibidos, y pueden disminuir.

Las ciudades tienen cuatro estilos visuales persistentes: villa mediterránea, ciudad jardín, centro urbano y barrio industrial. Una semilla propia varía edificios, orientaciones, jardines, densidad y trazado de calles; su identidad se mantiene al crecer y al cargar, incluidas las partidas antiguas. Hay siete edificios nuevos y un parque en `assets/sprites/city-v2/`, además de ocho coches cenitales en `assets/sprites/vehicles-v2/`. Se dibujan con el atlas y las mallas por bloques para conservar el rendimiento del zoom.

Los edificios se generan junto a calles residenciales o avenidas urbanas, sin ocuparlas. Las parcelas que no tienen una vía adyacente conservan suelo libre y arbolado disperso; los parques con fuente son puntuales. El centro es una vía transitable y el edificio cívico ocupa una parcela contigua. Las calles son carreteras reales: usan los mismos sprites de recta, curva y cruce, capacidades, conservación, semáforos y cierres que el resto de la red. Los coches circulan por ellas dentro de la ciudad; edificios y parques no forman parte de las rutas.

El plano parte de una sola calle principal y añade un cruce, un ramal o una pequeña manzana de servicio según su estilo, semilla y tamaño. Las calles paralelas tienen al menos dos parcelas entre ellas (`CITY_STREET_BLOCK_SPACING = 3`); no se permiten superficies de asfalto de 2 × 2. En planos nuevos de radio 2 o mayor, las calles ocupan como máximo el 40 % de la superficie urbana. Las avenidas se reservan a la calle principal. Cada ciudad genera de dos a cuatro salidas, cada una con una prolongación exterior gratuita de tres casillas. **Todas las carreteras que salen de la red urbana son conectores**, incluidas las salidas construidas por el jugador; ya no hay una lista limitada de lados autorizados. Los conectores se calculan a partir de las carreteras existentes y sus extremos se marcan con un círculo y una flecha. G / R3 lleva al acceso principal de la siguiente ciudad.

Al crecer o reducirse, la ciudad sincroniza su plano y retira los tramos automáticos sobrantes. Las vías generadas guardan su procedencia para distinguirlas de las construcciones y modificaciones del jugador. Al cargar ciudades del primer generador urbano se limpia la malla automática antigua; se conservan las conexiones a carreteras exteriores, sus corredores de acceso, obras, cierres y semáforos. Un coche sobre un tramo automático retirado se traslada a la calle urbana más cercana manteniendo su viaje. Las calles urbanas generadas y los accesos están protegidos frente al abandono, y su demolición explícita se conserva al cargar. Las partidas antiguas reciben calles transitables; un coche guardado sobre un antiguo edificio decorativo se sitúa en la calle más cercana de su ciudad, conservando destino e identidad.

## Accidentes, clima y abandono

Los incendios, nevadas y accidentes muestran un aviso con su ubicación. **A / Enter** lleva al evento; **B / Esc** descarta únicamente el aviso. Funciona con mando, teclado y botones de ratón, también sobre los menús. Los avisos permanecen hasta atenderlos y se presentan en orden; los sucesos repetidos de un mismo tipo y casilla se agrupan. Se conservan al guardar y cargar. Al ir al evento se mantiene el inicio de construcción pendiente; al descartar, se conserva el menú y la selección.

Cada uno de los 24 tipos tiene **nueve sprites adicionales**, manteniendo sus materiales y carriles: ardiendo, nevado, estropeado, muy estropeado, estropeadísimo, cortado, desapareciendo, rotonda y semáforo. Son 216 sprites adicionales; las rotondas miden 192×192 píxeles para su huella de 3×3. Hay también cuatro fotogramas de incendio y cuatro variantes de nieve. Los originales y prompts de ImageGen están en `assets/source/road-conditions/` y `assets/source/environment/`; los PNG de juego en las carpetas equivalentes de `assets/sprites/`.

Los porcentajes se comprueban **por coche cada 30 segundos simulados**, se suman si coinciden y se limitan al 100 %. Cada accidente resta **100 €** y detiene al coche **15 segundos**, conservando su destino. Un indicador rojo identifica al vehículo y la penalización aparece junto a la carretera.

| Condición | Riesgo añadido |
| --- | --- |
| Incendio | 30 % |
| Nieve | 30 % |
| Estropeada: conservación inferior al 75 % | 5 % |
| Muy estropeada: conservación inferior al 40 % | 15 % |
| Estropeadísima: conservación inferior al 15 % | 30 % |

Los tres niveles de desgaste son excluyentes; nieve y fuego pueden coincidir entre sí y con el desgaste. Por ejemplo, nieve + fuego + carretera muy estropeada suman 75 %. Las rotondas, los semáforos y el abandono no añaden un porcentaje propio: se aplican sus condiciones de nieve, fuego y conservación. Los umbrales iniciales de conservación están en `scripts/incidents.gd`.

Cada tres minutos simulados aparece una zona de nieve o un incendio cerca de la red. La nieve dura dos minutos. El incendio empieza en una casilla, se extiende a una vecina cada cinco segundos durante su primer minuto y cada casilla arde durante un minuto; después se extingue. Ambos fenómenos pueden ocupar la misma zona. J / Localizar última alerta lleva al foco más reciente.

Una carretera sin coches empieza a desaparecer tras diez minutos y lo hace gradualmente durante cinco minutos más, hasta retirarse de la red. Un coche parado también cuenta como uso. Reparar una vía restaura su conservación y reinicia su plazo. **Los accesos de ciudad están protegidos**, incluidos los que mejores. El uso de una parte de una rotonda mantiene el conjunto; una rotonda completamente abandonada desaparece como objeto.

## Viajes, colas y controles de tráfico

La demanda se ha reducido: cada ciudad emite entre uno y tres viajes cada seis segundos simulados, según población. La primera conexión activa una salida inicial. Las colas y los viajes ya existentes conservan su destino; bajar la demanda afecta a las nuevas salidas.

Los ocho modelos de coche usan texturas individuales y una identidad estable durante todo el viaje. En acumulaciones de coches se evita superponer sus dibujos; se conserva la simulación de todos ellos, sus colas y sus estadísticas. Los coches detenidos conservan la orientación y los que circulan por rotondas giran de forma continua.

Cuando existe una conexión entre ciudades, sus destinos quedan activados y empiezan a generar viajes. Si posteriormente se pierde la ruta, las ciudades siguen generando coches hacia esos destinos. Los que circulaban se detienen al alcanzar el corte o toman una alternativa si existe; los nuevos siguen la última ruta conocida o esperan en el acceso. Conservan siempre su destino y continúan cuando vuelve a existir una ruta.

Los accesos llenos retienen la demanda dentro de la ciudad. El límite de 350 vehículos visibles acota la simulación; los coches adicionales quedan contabilizados en cola, sin descartarse. El bocadillo de un acceso muestra esa cola. La espera cuenta dentro de la duración del viaje, por lo que reduce el dinero recibido al completarlo. No hay una tarifa adicional por segundo de espera.

**Rotondas:** O activa su colocación en 3×3. Tienen ocho casillas transitables con circulación en sentido único y una isla central reservada. Cuestan nueve veces el precio por casilla del tipo de vía elegido. Para convertir carreteras existentes, desvía el tráfico, vacía la zona y ciérralas primero. Al seleccionar cualquier parte puedes cerrar, abrir, reparar o mejorar el conjunto.

**Semáforos:** T instala o abre la configuración de uno existente. Permiten ajustar por separado el verde norte/sur y este/oeste entre 1 y 120 segundos, y encenderlos o apagarlos. Inicialmente son diez segundos por eje. Los coches esperan antes de entrar si su dirección tiene rojo. Se pueden configurar con ratón, teclado y cruceta del mando; el catálogo ofrece también los modos de construcción especiales.

**Bocadillo:** aparece automáticamente en la carretera seleccionada con teclado/mando o bajo el ratón. Muestra tipo, carriles, coches presentes/capacidad, conservación, velocidad, riesgo por intervalo, clima, tiempo sin uso, obras y protección de acceso; los semáforos tienen un botón de configuración. Pulsar el texto informativo no construye una carretera detrás.

## Barra, menú y controles

La barra inferior agrupa **Construir**, **Cerrar / abrir**, **Reparar**, **Destruir** y **Talar** en el mismo orden que los controles 1–5 y LB/RB. Cada acción tiene un icono vectorial propio y una etiqueta debajo, con la selección destacada y una ayuda contextual al pasar el ratón. El selector central muestra el tipo de vía, su aspecto, los carriles y el precio por casilla. A su derecha hay accesos a **Rotonda**, **Semáforo**, **Mejorar**, **Deshacer** y **Menú**; mejorar y deshacer indican cuándo están disponibles. El botón de cierre cambia a **Abrir** al seleccionar una carretera cerrada. Los iconos de mapa, objetivos, servicios, pausa y zoom comparten el mismo estilo. El pie adapta sus indicaciones a teclado o mando. Iconos editables: `assets/ui/icons/`; presentación: `scripts/toolbar.gd`.

La construcción normal siempre requiere **dos extremos distintos**: A / Enter fija el inicio, mueve el cursor y vuelve a confirmar para construir el tramo. B / Esc cancela el inicio. X / R cambia el orden de los ejes del trazado. Puedes conservar el inicio mientras consultas el mapa o te desplazas a otra ciudad.

**Destruir** cuesta el 25 % del precio de construcción y tarda 5 segundos simulados. Cierra la vía al aceptar el trabajo; sus coches conservan destino y posición y esperan hasta que vuelva a existir una conexión desde esa casilla. La rotonda se demuele completa. **Talar** cuesta 20 € por casilla de bosque y tarda 3 segundos simulados. Ambos trabajos muestran progreso y se guardan aunque estén sin terminar. Los accesos siguen protegidos frente al abandono; una demolición explícita no reaparece al cargar.

El menú principal da acceso a Ciudades, Mapa, Estadísticas, Contabilidad, Objetivos, Red y servicios, Escenarios y Trucos. Las cuatro pantallas de consulta son:

- **Ciudades:** listado paginado con habitantes, viajes recibidos, accesos, colas, conexión actual y botón para ir al acceso principal. El estado actual no se confunde con los destinos históricos que siguen generando demanda.
- **Mapa:** terreno de la región, carreteras, ciudades, cámara y destino seleccionable. Permite desplazarse a cualquier punto, ampliar, reducir y encuadrar el territorio conocido o el mapa entero. Muestrea terreno sin llenar la caché de bloques.
- **Estadísticas:** ciudades, población, viajes, coches, colas, bloqueos, carreteras, accidentes, clima y tiempo simulado.
- **Contabilidad:** ingresos, gastos, resultado, caja, desglose por concepto y hasta 1.000 movimientos recientes filtrables. Los totales se conservan completos; en partidas anteriores los gastos sin detalle aparecen como «Anterior sin desglose».

| Acción | Teclado / ratón | Mando / Steam Deck |
| --- | --- | --- |
| Mover selección | WASD / flechas | Stick izquierdo / cruceta |
| Desplazamiento rápido | Mantener Mayús | Mantener la dirección del stick |
| Acción / fijar inicio / confirmar tramo | Enter / E / clic | A |
| Orden de los ejes del tramo | R / X | X |
| Herramienta anterior / siguiente | Q / Tab; 1–5 herramientas, 6 menú | LB / RB (L1 / R1); excluye Menú |
| Selector del tipo de carretera | Y / V | Y con Construir seleccionado |
| Elegir carretera en catálogo | Flechas, Enter | Cruceta / stick, A |
| Modo carretera / rotonda / semáforo | Botones del catálogo / X | X dentro del catálogo |
| Zoom | +/−, rueda, RePág / AvPág | LT / RT (L2 / R2) |
| Siguiente acceso de ciudad | G | R3 |
| Pausa / reanudar | Espacio | L3; recupera la velocidad anterior |
| Velocidad pausa / 1× / 2× / 4× / 8× | F; botón superior | Botón de velocidad en pantalla |
| Menú principal | 6 / F10; botón Menú | ☰ (Menu / Start) |
| Cancelar / volver / cerrar | B / Esc / clic derecho | B |
| Reparar / mejorar al tipo elegido | Enter / U con vía cerrada | A / X con Arreglar seleccionado |
| Rotonda / semáforo / carretera normal | O / T / P | Y → catálogo, X cambia modo, A confirma |
| Inspección de selección | I; bocadillo automático | Bocadillo automático |
| Localizar nieve / incendio reciente | J | — |
| Mapa interactivo | M | View |
| Mover mapa / ir al destino | WASD / flechas, Enter; clic selecciona, doble clic va; arrastre derecho desplaza | Stick / cruceta, A |
| Encuadrar mapa conocido / entero | X / Y dentro del mapa | X / Y dentro del mapa |
| Guardar / cargar | F5 / F9; X guarda en el menú; Enter activa Cargar | X guarda; Cargar con selección y A |
| Ayuda | H; botón del menú | Y en el menú principal; o seleccionar Ayuda y A |
| Trucos | F8; opción del menú | Menú → Trucos; cruceta / stick y A |
| Nueva región | N y repetir para confirmar | — |

En la lista de ciudades, ↑ / ↓ elige, A / Enter va y X / Y cambia página. En Contabilidad, la cruceta / stick elige filtros y botones de desplazamiento; A los activa y LB/RB o X/Y cambian el filtro. El menú no detiene el tiempo; usa pausa cuando lo necesites.

### Controles de Steam Deck

La navegación de mando se procesa antes de la interfaz de Godot, por una sola vía. El foco azul marca el botón que ejecutará A, incluidos los controles inferiores de Guardar, Cargar, Ayuda y Velocidad. No depende de haber dibujado ya el menú. Se descartan también los Enter/Esc/clic duplicados que Steam Input pueda emitir junto a un botón de mando. El stick usa zona muerta y repetición con pausa inicial; mantener A no confirma una segunda pantalla y el movimiento pasivo del ratón no cambia la selección del mando. Las confirmaciones empiezan en Cancelar. En el menú principal, **X guarda** y **Y abre Ayuda**; cargar requiere seleccionar Cargar y pulsar A. En escenarios, B cancela primero la preparación del reto y después cierra la pantalla.

El zoom de juego llega ahora a **0,5 píxeles por casilla**: permite ver **16 veces más anchura y 256 veces más superficie** que el mínimo anterior de 8 píxeles. Por debajo de ese mínimo anterior se usa una vista regional con terreno muestreado, carreteras y marcadores de ciudades, vehículos e incidentes. El número de muestras es fijo y no se generan mallas de millones de casillas. Al acercarse vuelve el detalle pixel art. El zoom se conserva al guardar y cargar, y el desplazamiento se adapta al alejamiento.


**☰ (Menu/Start)** abre el menú principal y vuelve a cerrarlo. **View** abre/cierra el mapa. **B** vuelve a la pantalla anterior, cierra un cuadro, descarta un aviso o cancela el trazado o modo de construcción; en el mapa de juego, si no hay nada que cancelar, no hace nada. B nunca abre el menú desde el juego.

**L1/R1** recorren únicamente las cinco herramientas de construcción, cierre, reparación, demolición y tala. Dentro de un panel cambian de página, columna, filtro o pestaña, manteniéndolo abierto. **L3** pausa/reanuda y recupera la velocidad que había antes de pausar. **L2/R2** controlan el zoom; **R3** va a la siguiente ciudad. **A** confirma y **Y** abre el catálogo desde cualquier herramienta. **X** cambia el trazado; en el catálogo cambia carretera/rotonda/semáforo y, con Reparar, permite mejorar. La consola de trucos es una opción seleccionable del menú, con A para abrirla y B para cerrarla.

En teclado, **6/F10** abre el menú; **B/Esc/clic derecho** solo cierran, vuelven o cancelan. **Q/Tab** recorren las cinco herramientas sin abrir el menú; Tab dentro de un panel recorre su selección.

## Trucos

Durante una partida, F8 abre el cuadro de trucos. Escribe un código y pulsa Enter, o selecciona uno de sus botones. F8, Esc o B lo cierran. La simulación se detiene mientras está abierto; al cerrarlo recupera su velocidad salvo que uses un truco de velocidad. En Steam Deck puedes usar los botones sin escribir, o Steam + X para abrir el teclado.

| Código | Efecto |
| --- | --- |
| `moremoney` | Añade 100.000 €, registrados como Trucos en Contabilidad. |
| `fire` | Inicia un incendio en la casilla seleccionada, con la propagación habitual. |
| `snow` | Genera nieve en un radio de seis casillas alrededor de la selección. |
| `sun` | Elimina la nieve y los incendios activos. |
| `repair` | Repara inmediatamente la carretera o rotonda seleccionada, conservando su estado abierto/cerrado. |
| `fast` / `normal` / `pause` | Deja la velocidad al máximo, a ×1 o en pausa al cerrar. |
| `reveal` | Descubre 5 × 5 regiones alrededor de la selección, incluyendo nuevas ciudades. |
| `help` | Muestra los códigos disponibles. |

## Configurar el juego

Edita `scripts/world_settings.gd` y reinicia la ejecución. Los parámetros están agrupados y comentados, con tiempos en segundos de simulación (salvo el autoguardado, que usa segundos reales), importes en euros y riesgos entre 0 y 1. Estos son los ajustes básicos de generación:

```gdscript
const INITIAL_SIDE = 2048            # Casillas por lado; múltiplo de 1024.
const INITIAL_CITY_COUNT = 400       # Ciudades al empezar.
const MIN_CITY_DISTANCE = 100        # Separación mínima entre centros.
const START_CITY_DISTANCE = 100      # Distancia de la pareja inicial.
const EXPLORATION_CITY_GRID = 7      # Hasta 7 × 7 ciudades por región nueva.
```

Además puedes ajustar:

| Grupo | Ejemplos de parámetros |
| --- | --- |
| Terreno | `TERRAIN`: frecuencia del relieve, umbrales de bosques/montañas/rocas, separación y anchura de ríos. |
| Ciudades | `START_CITY_RADIUS`, `NEW_CITY_RADIUS`, `CITY_ACCESS_LENGTH`, tipos de calle y avenida, población y crecimiento/decrecimiento. |
| Viajes | `DEMAND_INTERVAL`, `DEMAND_BASE_CARS`, `DEMAND_MAX_CARS`, `DEMAND_POPULATION_STEP`, `MAX_VISIBLE_CARS`. |
| Economía | `STARTING_MONEY`, `TRIP_BASE_FARE`, `TRIP_FARE_PER_CELL` y multiplicadores según duración del viaje. |
| Obras | Costes y tiempos de mejora, reparación, demolición y tala; desgaste de las vías y verdes iniciales de los semáforos. |
| Accidentes | Intervalo, coste, duración de la parada y riesgos por nieve, fuego y deterioro. |
| Clima y abandono | Activación, frecuencia, duración, propagación, radio de nieve y tiempos de desaparición por desuso. |
| Guardado | `AUTOSAVE_ENABLED` activa el guardado automático periódico y al salir; `AUTOSAVE_INTERVAL` cambia su frecuencia. El guardado manual sigue disponible. |

Para menos tráfico, aumenta `DEMAND_INTERVAL`; para más ingresos, sube `TRIP_FARE_PER_CELL`. Para repetir un mundo, usa `RANDOM_WORLD_SEED = false` y cambia `WORLD_SEED`. Los precios, capacidades, velocidades y tiempos de construcción **por tipo de carretera** siguen en `scripts/catalog.gd`.

El dinero inicial, la semilla y la distribución inicial requieren **partida nueva**. Cada guardado conserva sus parámetros de terreno y sus reglas de clima/abandono, incluso si cambias los valores por defecto después; los guardados anteriores reciben sus parámetros históricos de terreno. Los demás ajustes de equilibrio se aplican también a partidas cargadas; los trabajos ya iniciados conservan su tiempo restante y los semáforos existentes conservan sus tiempos. El archivo valida rangos básicos al iniciar y muestra un error indicando qué revisar si un valor no es válido.

La región inicial tiene ahora 2048 × 2048 casillas (antes 3072 × 3072). Los emplazamientos se distribuyen de forma escalonada, con variación y orden aleatorio según la semilla, priorizando praderas y bosques; si hace falta, se preparan parcelas sobre otros terrenos para alcanzar el número solicitado. Si pides más ciudades de las que caben respetando la separación mínima, se generan las que caben y Godot muestra un aviso. Amplía el tamaño o reduce la separación para admitir más. Los guardados existentes conservan su mapa y ciudades.

## Guardado y compatibilidad

Esta región ampliada usa **un guardado nuevo v2**, `user://entre_ciudades_v2.save`. La antigua partida `entre_ciudades.save` se conserva intacta; no se estira ni se pierde su red de carreteras. La versión actual comienza en la región nueva si todavía no hay guardado v2. Los guardados antiguos conservan su región de 16.384 × 16.384 y pueden ampliarse desde sus bordes. La distribución más cercana y la región inicial compacta se aplican a las partidas nuevas. La partida v2 se recupera con Cargar partida en el inicio; durante la sesión se guarda cada minuto real y al cerrar. Se conservan los coches, destinos, colas, accidentes pendientes, nieve, incendios, abandono, rotondas, semáforos, trabajos de demolición y tala, y contabilidad. Las rutas se recalculan desde la posición guardada; no se cobran viajes interrumpidos ni desaparecen sus colas al cargar.

Interfaz diseñada a 1280 × 800, renderer Compatibility y eventos estándar de mando de Godot. Se incluye el perfil de exportación Linux x86_64. Para generar un ejecutable necesitas las plantillas de exportación correspondientes a la versión de Godot. Se ha probado el proyecto en macOS; falta validación en una Steam Deck física. No integra Steamworks.

El equilibrio inicial contempla 80.000 €, 400 ciudades generadas desde el inicio y nuevas ciudades al explorar, población actualizada cada minuto simulado y 350 vehículos visibles más las colas pendientes. No hay modelo individual de adelantamientos, cálculo estructural de puentes ni sonido.

## Rendimiento del zoom

El terreno y los edificios se dibujan en bloques de 32 × 32 con mallas y un atlas compartido, conservando los sprites originales. Mover la cámara o cambiar el zoom transforma los bloques ya dibujados. La caché mantiene como máximo 48 bloques y actualiza solo los afectados por cambios de terreno, tala, construcción o crecimiento urbano; también invalida las riberas vecinas. Las carreteras visibles, coches, obras, clima e interfaz conservan sus capas y animación independientes. Las previsualizaciones de tramos largos se recortan a la cámara; la construcción sigue usando el trazado completo.

En la prueba gráfica pausada a 1280 × 800, sin límite de FPS, en un Mac M1 Pro, el zoom mínimo pasó de unos 122 ms a unos 3 ms por fotograma. El desplazamiento dio una mediana cercana a 3 ms, con picos al entrar en bloques nuevos. Son medidas de esta escena y máquina; no equivalen a una prueba física en Steam Deck.

## Verificación y recursos

```sh
godot --headless --path . --script tests/smoke.gd -- --test-mode
godot --headless --path . --script tests/starting_cities.gd -- --test-mode
godot --headless --path . --script tests/road_connections.gd -- --test-mode
godot --headless --path . --script tests/presentation.gd -- --test-mode
godot --headless --path . --script tests/visual_refresh.gd -- --test-mode
godot --headless --path . --script tests/expanding_world.gd -- --test-mode
godot --headless --path . --script tests/cheats.gd -- --test-mode
godot --headless --path . --script tests/urban_roads.gd -- --test-mode
godot --headless --path . --script tests/city_layout.gd -- --test-mode
godot --headless --path . --script tests/world_settings.gd -- --test-mode
python3 tests/check_settings_overrides.py /ruta/al/ejecutable/Godot
godot --headless --path . --script tests/incidents.gd -- --test-mode
godot --headless --path . --script tests/condition_assets.gd -- --test-mode
godot --headless --path . --script tests/navigation_toolbar.gd -- --test-mode
godot --headless --path . --script tests/title_screen.gd -- --test-mode --title-screen
```

Las pruebas usan un guardado separado, lo eliminan al terminar y no tocan la partida del jugador. Cubren mundo por bloques, separación entre ciudades, accesos y restricciones de conexión, obras, viajes e ingresos, reparación, mejora dentro de una casilla, puentes, crecimiento de accesos, guardado, sprites, topologías, zoom y efectos de ingresos.

`tests/capture_title.gd` captura el inicio con `-- --test-mode --title-screen`; esta opción permite probar el arranque sin tocar la partida del jugador. `tests/capture_toolbar.gd` captura la barra, el menú y sus cuatro pantallas. `tests/navigation_toolbar.gd` comprueba los controles, tramos, trabajos, guardado, caja, navegación y conexión actual. `tests/capture_incidents.gd` verifica visualmente los estados, el bocadillo, los semáforos y una cola real tras un corte. `tests/capture.gd` genera capturas reales con una sesión gráfica y `-- --test-mode`. `tools/prepare_roads_v4.py` limpia y registra las láminas generadas, usando Pillow y NumPy. `tools/prepare_conditions.py` prepara los 216 estados y los efectos. El arte original se genera mediante la herramienta integrada ImageGen; los scripts solo recortan, eliminan magenta, alinean y escalan con vecino más próximo. Las fuentes de arte, las pruebas y las herramientas están excluidas de la importación/exportación de Godot mediante `.gdignore`.

La validación de caché y el benchmark necesitan una sesión gráfica:

```sh
godot --path . --script tests/render_cache.gd -- --test-mode
godot --path . --script tests/zoom_benchmark.gd -- --test-mode --moving
```

`tests/capture_visual_refresh.gd` captura los nuevos cruces, los cuatro estilos de ciudad y coches reales en la conexión inicial. `assets/source/visual-refresh/README.md` documenta el arte y su preparación.

La calle residencial utiliza un kit específico centrado y simétrico, con estados alineados y uniones compartidas. Arte y prompts: `assets/source/residential-centered/README.md`. Verificación: `tests/residential_centered.gd`; captura: `tests/capture_residential.gd`.

`tests/expanding_world.gd` verifica regiones nuevas y revisitadas, terreno y carreteras negativos, IDs de rutas sin colisiones, guardado y migración, demanda reducida, identidad de coches y texto de ingresos sin monedas. `tests/capture_expansion.gd` valida gráficamente el mapa ampliado y varios fotogramas de tráfico en movimiento.
