package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"
import m "core:math/linalg"

import "core:c"
import "core:mem"
import "core:slice/heap"
import "core:math"
// ==== CONSTANTS =============================================================

POINT_SPEED          :: 200   // px/s
FIGURE_MIN_FRECUENCY :: 0.016 // Hz
FIGURE_MAX_FRECUENCY :: 11 // Hz
COUNTER_INF          :: -1

FIGURE_MAX_SIDES     :: 16
FIGURE_POINT_RADIUS  :: 5.0
FIGURE_MIN_RADIUS    :: 30
FIGURE_SELECTOR_SIZE :: 15

FIGURE_VIEW_COLOR         :: rl.WHITE
FIGURE_BEAT_COLOR         :: rl.SKYBLUE
FIGURE_FIRST_POINT_COLOR  :: rl.GREEN
FIGURE_SELECTED_COLOR     :: rl.RED
FIGURE_LINE_SIZE          :: 3.0
FIGURE_SELECTED_LINE_SIZE :: 8.0

SELECTION_RECT_COLOR :: color { 100, 100, 100, 100 }
LINK_ARROW_HEAD_LEN  :: 15.0
LINK_ARROW_SIZE      :: 1.0

// ==== FIGURE DATA ===========================================================

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,
	frecuency: f32,
	
	// Para los enlaces
	next_figure: ^Regular_Figure,
	previous_figure: ^Regular_Figure,
	is_active: bool,

	// Indica en qué segmento está el punto: [0, n-1]
	point_seg_index: uint,
	// Indica el progreso dentro del segmento actual
	point_progress: f32,
	// Indica el número de ciclos que le queda a la figura (infinito es -1)
	point_counter: int,
	// Indica el contador inicial de la figura (para saber a qué valor resetear)
	point_counter_start: int,

	notes: [FIGURE_MAX_SIDES]Music_Notes,
	percussions: [FIGURE_MAX_SIDES]Percussion,
	instrument: Instrument,
}

// ==== INPUT UPDATE ==========================================================

// WARN: Solo poner código relacionado con el ratón, no eventos de teclado
// WARN: Los chequeos de colisiones con el ratón se deben hacer en screen space
update_figure_selection_tool :: proc() {
	using game_state

	// Ignorar eventos mientras se está en la UI
	if state != .Move_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), ui.panel_create_figure) {
		return
	}

	if state == .Selected_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), ui.panel_figure) {
		return
	}

	// Como se puede saltar a este modo desde cualquier otro, poner esto aquí
	if rl.IsMouseButtonPressed(.RIGHT) {
		state = .Rectangle_Multiselection
		current_figure = nil
		clear(&selected_figures)
	}

	switch state {
	case .View: {
		assert(current_figure == nil && len(selected_figures) == 0, "En modo .View, current_figure debe ser nil")

		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonDown(.LEFT) {
			// Comprobar si se seleccionan figuras
			selected := select_figure()
			
			if selected != nil {
				// Seleccionar figura
				current_figure = selected
				state = .Selected_Figure

			} else {
				// Crear nueva figura
				state = .Edit_Figure
				new_center := to_world(game_state.camera, rl.GetMousePosition())

				ensure(len(figures) < MAX_FIGURES, "Maximum figures reached")
				append(&figures, Regular_Figure {
					// Posición dada por el usuario
					center = new_center,
					radius = new_center,

					// Características heredadas de la UI de creación
					n                   = ui.creation_n_sides,
					instrument          = ui.creation_instrument,
					point_counter_start = ui.creation_counter,
					point_counter       = ui.creation_counter,

					// Valores por defecto que no son 0
					frecuency = FIGURE_MIN_FRECUENCY,
					is_active = true,
				})

				current_figure = &figures[len(figures)-1]
			}
		}
	}

	case .Edit_Figure: {
		assert(current_figure != nil && len(selected_figures) == 0, "Modo .New_Figure requiere una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			current_figure.radius = to_world(camera, rl.GetMousePosition())
			update_figure_frecuency(current_figure)

		} else if !is_figure_big_enough(current_figure^) {
			// Si la figura es muy pequeña, salir
			set_msg("The figure was deleted because it was too small\nZoom in to make faster shapes")
			delete_current_figure()
			current_figure = nil
			state = .View

		} else {
			state = .Selected_Figure
		}
	}

	case .Move_Figure: {
		assert(current_figure != nil && len(selected_figures) == 0, "Modo .Move_Figure requiere una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			diff := current_figure.center - current_figure.radius
			current_figure.center = to_world(camera, rl.GetMousePosition())
			current_figure.radius = current_figure.center - diff
		} else {
			state = .Selected_Figure
		}
	}

	case .Multiselection_Move: {
		assert(current_figure != nil && len(selected_figures) != 0, "Modo .Multiselection_Move requiere varias figuras seleccionadas y current_figure a la que hace click el ratón")

		if rl.IsMouseButtonDown(.LEFT) {
			mouse_world := to_world(camera, rl.GetMousePosition())
			moved := mouse_world - current_figure.center 

			for &f in selected_figures {
				f.center += moved
				f.radius += moved
			}
		} else {
			state = .Multiselection
			current_figure = nil
		}
	}

	case .Selected_Figure: {
		assert(current_figure != nil, "Modo .Selected_Figure require una figura seleccionada")

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse := rl.GetMousePosition()

			if rl.CheckCollisionPointCircle(mouse, to_screen(camera, current_figure.radius), FIGURE_POINT_RADIUS) {
				// Click en el vértice para cambiar su tamaño
				state = .Edit_Figure

			} else if is_figure_selected(mouse, current_figure^) {
				// Arrastrar la figura
				state = .Move_Figure

			} else if collision, segment, progress := check_collision_figure(mouse, current_figure^); collision {
				// Cambiar la posición del punto actual
				current_figure.point_seg_index = segment
				current_figure.point_progress = progress

			} else {
				// Sino, mirar si se ha seleccionado otra figura
				selected := select_figure()

				if selected == nil {
					// Deseleccionar si se hace click en otro lado
					current_figure = nil
					state = .View

				} else if rl.IsKeyDown(.LEFT_SHIFT) {
					// Borrar selección de antes
					clear(&selected_figures)

					// Añadir las figuras seleccionadas: la anterior y la nueva
					assert(selected != current_figure, "unreachable: se manejó este caso en otra rama")
					append(&selected_figures, current_figure)
					append(&selected_figures, selected)
					current_figure = nil

					// Iniciar multiselección
					state = .Multiselection

				} else {
					assert(selected != current_figure, "unreachable: se manejó este caso en otra rama")
					// Seleccionar otra figura
					current_figure = selected
				}
			}
		}
	}

	case .Multiselection: {
		assert(current_figure == nil && len(selected_figures) != 0, "Modo .Multiselection requiere current_figure a nil y figuras en select_figures")

		if rl.IsMouseButtonPressed(.LEFT) {
			selected := select_figure()

			if selected == nil {
				// Se hizo click fuera de la selección para quitarla
				clear(&selected_figures)
				state = .View

			} else if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
				// Comprobar si ya existe esa figura en la selección
				index_in_selection := -1
				for fig, i in selected_figures {
					if fig == selected {
						index_in_selection = i
						break
					}
				}

				// Añadir si no está en la selección, quitar si está
				if index_in_selection == -1 {
					append(&selected_figures, selected)
				} else {
					unordered_remove(&selected_figures, index_in_selection)
				}
			} else {
				// Comprobar si ya existe esa figura en la selección
				index_in_selection := -1
				for fig, i in selected_figures {
					if fig == selected {
						index_in_selection = i
						break
					}
				}

				if index_in_selection == -1 {
					state = .Selected_Figure
					current_figure = selected
					clear(&selected_figures)
				} else {
					state = .Multiselection_Move
					// Usar current_figure como la que está en el ratón
					current_figure = selected
				}
			}
		}
	}

	case .Rectangle_Multiselection: {
		assert(current_figure == nil && len(selected_figures) == 0, "En modo .Rectangle_Multiselection, no debe haber nada seleccionado")

		if rl.IsMouseButtonPressed(.RIGHT) {
			selection_rect_center = rl.GetMousePosition()
			selection_rect = {}

		} else if rl.IsMouseButtonDown(.RIGHT) {
			mouse := rl.GetMousePosition()

			// Calcular el rectángulo de selección correcto
			base := v2 { min(mouse.x, selection_rect_center.x), min(mouse.y, selection_rect_center.y) }
			top := v2 { max(mouse.x, selection_rect_center.x), max(mouse.y, selection_rect_center.y) }
			size := top - base

			selection_rect = {
				base.x, base.y, size.x, size.y,
			}

		} else if rl.IsMouseButtonReleased(.RIGHT) {
			// PERF: esto es bastante ineficiente porque requiere iterar por
			// todas las figuras. Quizá se podría hacer en update_figure_state...
			for &f in figures {
				if rl.CheckCollisionPointRec(f.center, selection_rect) {
					append(&selected_figures, &f)
				}
			}

			if len(selected_figures) == 0 {
				state = .View

			} else if len(selected_figures) == 1 {
				state = .Selected_Figure
				current_figure = selected_figures[0]
				clear(&selected_figures)

			} else {
				state = .Multiselection
			}
		}
	}
	}
}

update_figure_link_tool :: proc() {
	using game_state
	// Esta herramienta solo funciona al hacer click
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}

	selected := select_figure()

	// ==== Primer paso: seleccionar una figura ====

	// Si se hizo click en otro lado, cancelar la selección
	if selected == nil {
		current_figure = nil
		return
	}

	// Si la figura de partida tiene un contador infinito, nunca podrá pasar a
	// la siguiente figura. Avisar al usuario del problema
	if selected.point_counter == COUNTER_INF {
		current_figure = nil
		set_msg("This figure will never end", err = true)
		return
	}

	// Almacenar figura seleccionada para crear el siguiente link
	if current_figure == nil {
		current_figure = selected
		return
	}

	// ==== Segundo paso: seleccionar otra figura ====

	// Borrar el link si se hace consigo misma
	if selected == current_figure {
		// Borrar el link con la siguiente figura
		next := current_figure.next_figure
		if next == nil do return
		current_figure.next_figure = nil

		// Borrar el backlink anterior
		next.previous_figure = nil

		// Marcar la siguiente como activa, porque ya no hay enlaces
		// bloqueándola (ya no sería cierto si se permiten varios links a la
		// misma)
		next.is_active = true

		// Y cancelar la selección
		current_figure = nil
		return
	}

	// Si el enlace es el mismo, no hacer nada
	if current_figure.next_figure == selected {
		current_figure = nil
		return
	}

	// No permitir que dos figuras apunten a una misma figura: se
	// sobreescribiría el puntero `previous_figure`
	// TODO: permitir? Entonces previous_figure: [dynamic]^Regular_Figure
	if selected.previous_figure != nil {
		set_msg("The figure is already linked", err = true)
		current_figure = nil
		return
	}

	// ==== Crear un nuevo link ====

	// Borrar el backlink de la figura que estaba antes enlazada
	if current_figure.next_figure != nil {
		current_figure.next_figure.previous_figure = nil
	}

	// Crear el enlace con la nueva figura
	current_figure.next_figure = selected

	// Crear el backlink
	selected.previous_figure = current_figure

	// Desactivar la figura que recibe el link
	selected.is_active = false

	// Ahorar mirar si hacia atrás hay una figura activa
	f := current_figure
	for !f.is_active && f.previous_figure != nil {
		f = f.previous_figure

		// Hemos encontrado un bucle si volvemos al inicio.
		// En tal caso, como creamos el link desde current_figure a selected,
		// selected debería estar ejecutándose ahora
		if f == selected {
			selected.is_active = true
			break
		}
	}

	// Si no había un bucle, resetear la figura apuntada, para que empiece de 0
	if !selected.is_active {
		selected.point_counter = selected.point_counter_start
		selected.point_progress = 0
	}

	// Y cancelar la selección
	current_figure = nil
}

// ==== STATE UPDATE ==========================================================

update_figure_state :: proc(fig: ^Regular_Figure) {
	// No procesar figuras inactivas
	//
	// Antes el chequeo era que no tuviese contador y que la figura anterior
	// tenga aún contador:
	//
	//    fig.point_counter == 0 || (fig.previous_figure != nil && fig.previous_figure.point_counter != 0)
	//
	if !fig.is_active {
		return
	}

	// Técnicamente se puede calcular la frecuencia desde el radio y el número
	// de lados, pero así es más rápido.
	//
	// Funciones de Odin con precisión de nanosegundos (por si raylib es
	// demasiado poco preciso):
	//
	//     import "core:time"
	//     time.now() -> Time
	//     time.since(Time) -> Duration
	//
	fig.point_progress += rl.GetFrameTime() * fig.frecuency

	// Cambiar de vértice
	if fig.point_progress > 1.0 {
		// Mover el punto
		fig.point_progress = 0.0
		fig.point_seg_index += 1

		// Tocar el sonido
		if is_figure_big_enough(fig^) {
			sound_to_play: rl.Sound
			if fig.instrument != .Tambor {
				sound_to_play = game_state.SOUND_MATRIX[fig.instrument][fig.notes[Music_Notes(fig.point_seg_index-1)]]
			} else {
				sound_to_play = game_state.PERCUSSION_SOUNDS[fig.percussions[Percussion(fig.point_seg_index-1)]]
			}

			//Sensación de crecimiento linear en el volumen
			if game_state.ui.volume != 0 {
				rl.SetSoundVolume(sound_to_play, math.pow_f32(50, game_state.ui.volume)/50)
				rl.PlaySound(sound_to_play)
			}
			
		}else{
			set_msg("The figure will not play any sound unless it gets bigger.")
		}
		
		// Nuevo ciclo
		if fig.point_seg_index == fig.n {
			fig.point_seg_index = 0

			if fig.point_counter > 1 {
				// Decrementar contador si todavía tiene
				fig.point_counter -= 1

			} else if fig.point_counter == 1 {
				// Poner el contador a 0
				fig.point_counter = 0

				// Sino, pasar a inactivo y resetear el contador
				fig.is_active = false
				fig.point_counter = fig.point_counter_start

				// Dar el paso a la siguiente figura, si hay
				next := fig.next_figure
				for next != nil {
					// Si la siguiente tiene contador disponible, ejecutar esa
					// Sino, seguir buscando
					if next.point_counter != 0 {
						next.is_active = true
						break
					}

					// Ciclo encontrado, no entrar en bucle infinito
					if next == fig {
						break
					}

					next = next.next_figure
				}
			}
		}
	
	}
}

// ==== RENDER ================================================================

@(private="file")
render_regular_figure_common :: proc(
	fig: Regular_Figure,
	color,
	point_color: rl.Color,
	line_size := f32(FIGURE_LINE_SIZE),
	arrow_size := f32(LINK_ARROW_SIZE),
) {
	using game_state

	diff := fig.center - fig.radius

	// Transformar coordenadas del mundo a coordenadas en la pantalla
	screen_center := to_screen(camera, fig.center)
	screen_radius := m.vector_length(diff) * camera.zoom

	// No dibujar si está fuera de la pantalla
	// BUG: los enlaces no se muestran
	if screen_center.x + screen_radius < 0 ||
		screen_center.y + screen_radius < 0 ||
		screen_center.x - screen_radius > f32(window_size.x) ||
		screen_center.y - screen_radius > f32(window_size.y) {
		return
	}

	// Dibujar círculo de selección + indicador del contador
	if screen_radius > FIGURE_MIN_RADIUS {
		// Dibujar el "handle" que permite seleccionar y mover la figura
		c_screen_center := iv2 {c.int(screen_center.x), c.int(screen_center.y)}
		rl.DrawCircleLines(c_screen_center.x, c_screen_center.y, FIGURE_SELECTOR_SIZE, color)

		// Dibujar el contador
		counter_str := cstr_from_int(fig.point_counter)
		text_width := rl.MeasureText(counter_str, UI_FONT_SIZE)
		c_screen_center.x -= text_width/2
		c_screen_center.y -= UI_FONT_SIZE/2

		rl.DrawTextEx(
			font = game_state.ui.font,
			text = counter_str,
			position = v2 { f32(c_screen_center.x), f32(c_screen_center.y) },
			fontSize = UI_FONT_SIZE,
			spacing = LABEL_SPACING,
			tint = color,
		)

		// Dibujar línea teniendo en cuenta el círculo de selección para que no
		// se crucen las líneas
		if fig.n == 2 {
			screen_diff := to_screen(camera, diff)

			// Vector que apunta al círculo de selección
			screen_selector := m.normalize0(screen_diff) * FIGURE_SELECTOR_SIZE

			// Los puntos alejados del centro
			out1 := screen_center - screen_diff // = to_screen(camera, fig.radius)
			out2 := screen_center + screen_diff

			// Los puntos que están en la circunferencia de la selección
			in1 := screen_center - screen_selector
			in2 := screen_center + screen_selector

			rl.DrawLineEx(out1, in1, line_size/2, color)
			rl.DrawLineEx(out2, in2, line_size/2, color)
		}
	} else if fig.n == 2 {
		// Si no hay círculo de selección y es una línea, dibujarla completa
		screen_diff := to_screen(camera, diff)
		point1 := screen_center - screen_diff // = to_screen(camera, fig.radius)
		point2 := screen_center + screen_diff
		rl.DrawLineEx(point1, point2, line_size/2, color)
	}

	// Si la figura no es una línea, dibujar normal, tenga o no círculo de
	// selección
	if fig.n != 2 {
		rotation := m.atan(diff.y / diff.x) * m.DEG_PER_RAD

		// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
		if diff.x >= 0 do rotation += 180

		rl.DrawPolyLinesEx(
			center = screen_center,
			sides = c.int(fig.n),
			radius = screen_radius,
			rotation = rotation,
			lineThick = line_size,
			color = color,
		)
	}

	// Dibujar el punto
	{
		// Calcular puntos del segmento actual: igual que en el bucle
		angle1 := 2 * m.PI * f32(fig.point_seg_index)     / f32(fig.n)
		angle2 := 2 * m.PI * f32(fig.point_seg_index + 1) / f32(fig.n)

		point1 := fig.center - vec_rotate(diff, angle1)
		point2 := fig.center - vec_rotate(diff, angle2)

		// Ahora interpolar entre las dos posiciones
		// Ecuación vectorial de una recta: (x, y) = p1 + k * v
		line_vector := point2 - point1
		beat_point := point1 + fig.point_progress * line_vector
		beat_point = to_screen(camera, beat_point)

		rl.DrawCircle(c.int(beat_point.x), c.int(beat_point.y), FIGURE_POINT_RADIUS, point_color)
	}

	// Dibujar el enlace
	if fig.next_figure != nil {
		// Calcular los valores de la siguiente figura
		next_diff := fig.next_figure.center - fig.next_figure.radius
		screen_next_center := to_screen(camera, fig.next_figure.center)
		screen_next_radius := m.vector_length(next_diff) * camera.zoom

		// Calcular el vector entre los centros
		line_vector := screen_next_center - screen_center

		// Calcular el vector unitario
		screen_distance := m.vector_length(line_vector)
		if abs(screen_distance) < 1.0e-10 do return
		unit_line_vector := line_vector / screen_distance

		end, start: v2
		// Si la distancia es muy pequeña, dibujar línea entre los centros
		// directamente
		if screen_distance - 3*LINK_ARROW_HEAD_LEN < screen_radius + screen_next_radius {
			start = screen_center + unit_line_vector*FIGURE_SELECTOR_SIZE
			end = screen_center + unit_line_vector * (screen_distance - FIGURE_SELECTOR_SIZE)

		} else {
			// Sino, dibujar la línea entre los círculos que encierran las
			// figuras
			start = screen_center + unit_line_vector*screen_radius
			end = start + unit_line_vector * (screen_distance - screen_radius - screen_next_radius)
		}

		// Ahora hacer como una flecha al final de 60º de amplitud
		arrow1 := end + vec_rotate(-unit_line_vector, +m.PI/6) * LINK_ARROW_HEAD_LEN
		arrow2 := end + vec_rotate(-unit_line_vector, -m.PI/6) * LINK_ARROW_HEAD_LEN

		rl.DrawLineEx(start, end, arrow_size, color)
		rl.DrawLineEx(end, arrow1, arrow_size, color)
		rl.DrawLineEx(end, arrow2, arrow_size, color)
	}
}


render_regular_figure :: proc(fig: Regular_Figure, color: rl.Color, point_color := FIGURE_BEAT_COLOR, fade := true) {
	using game_state

	// Los parámetros son inmutables por defecto, pero con lo siguiente sí puedo
	// modificarlos
	color := color
	point_color := point_color

	// Cambiar los colores si el contador llegó a 0 o si la figura anterior
	// tiene INF
	if fade && !fig.is_active {
		color = {
			130,
			130,
			130,
			color.a,
		}
		point_color = color
	}

	render_regular_figure_common(fig, color, point_color)
}

render_selected_figure :: proc(fig: Regular_Figure, color: rl.Color) {
	using game_state

	render_regular_figure_common(
		fig = fig,
		color = color,
		point_color = color,
		line_size = FIGURE_SELECTED_LINE_SIZE,
	)

	screen_point1 := to_screen(camera, fig.radius)
	rl.DrawCircleLines(c.int(screen_point1.x), c.int(screen_point1.y), FIGURE_POINT_RADIUS, color)

	// Mejor no dibujar el resto porque son más chequeos de colisiones,
	// realmente innecesarios porque el comportamiento se puede conseguir igual
	when false {
		// Dibujar los vértices
		// El siguiente es equivalente, pero menos código: for i := 0; i < int(n); i += 1
		//
		// Probablemente se pueda calcular de otra forma más eficiente, pero por
		// ahora así nos sirve.
		//
		// Todas las figuras regulares tienen los mismos ángulos, lo que implica que
		// podemos calcular así solo 2 puntos, tomar su vector y sumarlo N-1 veces
		// para encontrar el resto de puntos. Así es más rápido porque para los dos
		// primeros calculas varios (sen, cos), pero para el resto son solo sumas.
		//
		// Sin embargo, no sé si en el resultado final tendremos que dibujar los
		// vértices.
		diff := fig.center - fig.radius
		for i in 1 ..< fig.n {
			angle := 2 * m.PI * f32(i) / f32(fig.n)

			circle_center: v2
			circle_center.x = fig.center.x - (diff.x * m.cos(angle) - diff.y * m.sin(angle))
			circle_center.y = fig.center.y - (diff.x * m.sin(angle) + diff.y * m.cos(angle))
			circle_center = to_screen(camera, circle_center)

			rl.DrawCircleLines(c.int(circle_center.x), c.int(circle_center.y), FIGURE_POINT_RADIUS, color)
		}
	}
}

// ==== UTIL FUNCTIONS ========================================================

delete_current_figure :: proc() {
	using game_state
	assert(
		current_figure != nil && (state == .Edit_Figure ||
		state == .Selected_Figure ||
		state == .Move_Figure),
		"para borrar una figura, esta debe estar seleccionada",
	)

	// Borrar una figura causa que se reorganicen otras en el array, lo que
	// invalida los punteros. Existen los siguientes casos:
	//
	// 1.  Borrar el apuntado y que el apuntado sea el último:
	//     el puntero ahora apunta más allá del array ==> crasheos
	//
	// 2.  Borrar el apuntado y que el apuntado no sea el último:
	//     se cambiará el borrado por el último ==> el puntero es erróneo
	//
	// 3.  Borrar otro y el apuntado sea el último:
	//     el apuntado se moverá donde estaba otro ==> el puntero es erróneo
	//
	// 4.  Borrar otro y el apuntado no es el último:
	//     no hay problemas
	//
	// Lo mismo sucede en el otro sentido: si se borra el que apunta, el puntero
	// de vuelta (backlink) puntero ya no será válido.

	// Gestionar casos 1 y 2: eliminar links
	if current_figure.previous_figure != nil {
		current_figure.previous_figure.next_figure = nil
	}

	if current_figure.next_figure != nil {
		current_figure.next_figure.previous_figure = nil

		// Activar la siguiente figura
		if current_figure.is_active {
			current_figure.next_figure.is_active = true
		}
	}

	// Mueve el último elemento al actual y reduce la longitud en 1
	index := mem.ptr_sub(current_figure, &figures[0])
	unordered_remove(&figures, index)

	// Gestionar caso 3: solo aplica si el elemento borrado no es el último
	if index != len(figures) {
		// Ahora current_figure apunta al elemento que estaba al final. Debemos
		// poner el puntero de la figura que lo apuntaba a la nueva posición
		if current_figure.previous_figure != nil {
			current_figure.previous_figure.next_figure = current_figure
		}

		// Lo mismo pero para el backlink
		if current_figure.next_figure != nil {
			current_figure.next_figure.previous_figure = current_figure
		}
	}

	state = .View
	current_figure = nil
}

delete_multiselected_figures :: proc() {
	using game_state
	assert(
		current_figure == nil && state == .Multiselection,
		"No está en modo Multiselect",
	)

	// No se pueden borrar directamente, porque eso rompe los punteros: al
	// reorganizar las figuras después de borrar un elemento, otro puntero a
	// borrar después apuntará al lugar erróneo.
	//
	// Para solucionarlo, se calcularán todos los índices de los elementos y se
	// borrarán del final al principio.
	//
	// No es un algoritmo demasiado rápido pero al menos no depende del tamaño
	// de figures, solo del tamaño de la selección (que no debe ser muy grande).

	// Array dinámico del mismo tamaño que la selección que almacena los índices
	indices := make([dynamic]int, len(selected_figures), context.temp_allocator)
	for f, i in selected_figures {
		index := mem.ptr_sub(f, &figures[0])
		indices[i] = index
	}

	// Ordenar de mayor a menor
	less :: proc(a, b: int) -> bool { return a < b }
	heap.make(indices[:], less)
	// Y borrarlos por orden
	for _ in 0 ..< len(selected_figures) {
		// No romper los links: ver explicación en `delete_current_figure`
		current := &figures[indices[0]]
		if current.previous_figure != nil {
			current.previous_figure.next_figure = nil
		}
		if current.next_figure != nil {
			current.next_figure.previous_figure = nil
			if current.is_active {
				current.next_figure.is_active = true
			}
		}

		unordered_remove(&figures, indices[0])

		if indices[0] != len(figures) {
			if current.previous_figure != nil do current.previous_figure.next_figure = current
			if current.next_figure != nil do current.next_figure.previous_figure = current
		}

		heap.pop(indices[:], less)
		pop(&indices)
	}

	// Vaciar la selección
	clear(&selected_figures)
	state = .View
}


@(private="file")
check_collision_figure :: proc(pos: v2, fig: Regular_Figure) -> (collision: bool, segment: uint, progress: f32) {
	diff := fig.center - fig.radius

	pos_world := to_world(game_state.camera, pos)

	vertex1 := fig.radius
	vertex2: v2
	for i in 1 ..< fig.n {
		angle := 2 * m.PI * f32(i) / f32(fig.n)

		vertex2.x = fig.center.x - (diff.x * m.cos(angle) - diff.y * m.sin(angle))
		vertex2.y = fig.center.y - (diff.x * m.sin(angle) + diff.y * m.cos(angle))

		if rl.CheckCollisionCircleLine(pos, FIGURE_SELECTOR_SIZE, to_screen(game_state.camera, vertex1), to_screen(game_state.camera, vertex2)) {
			collision = true
			segment = i - 1
			break
		}

		vertex1 = vertex2
	}

	// El último segmento se hace con primer vértice
	if !collision && rl.CheckCollisionCircleLine(pos, FIGURE_SELECTOR_SIZE, to_screen(game_state.camera, vertex1), to_screen(game_state.camera, fig.radius)) {
		vertex2 = fig.radius
		collision = true
		segment = fig.n - 1
	}

	if !collision {
		return
	}

	// https://ericleong.me/research/circle-line/ (modificado)
	cx: f32
	v   := vertex2 - vertex1
	c1  := v.y * vertex1.x - v.x * vertex1.y
	c2  := v.y * pos_world.y + v.x * pos_world.x
	det := v.y * v.y + v.x * v.x
	if det != 0 {
		cx = (v.y * c1 + v.x * c2) / det
		// (cx, cy) = vertex1 + k * v => despejar k
		progress = (cx - vertex1.x) / v.x
	}

	return
}

@(private="file")
is_figure_selected :: #force_inline proc "contextless" (mouse: v2, fig: Regular_Figure) -> bool {
	// Hacerlo todo al cuadrado para no calcular sqrt()
	screen_center := to_screen(game_state.camera, fig.center)

	return is_figure_big_enough(fig) &&
		rl.CheckCollisionPointCircle(mouse, screen_center, FIGURE_SELECTOR_SIZE)
}

@(private="file")
select_figure :: proc() -> (selected: ^Regular_Figure) {
	using game_state

	mouse := rl.GetMousePosition()
	for &fig in figures {
		if is_figure_selected(mouse, fig) {
			selected = &fig
			break
		}
	}

	return
}

// Comprueba si la longitud del vector dado en world space cabe dentro de la
// distancia d en screen space
@(private="file")
is_figure_big_enough :: #force_inline proc "contextless" (fig: Regular_Figure) -> bool {
	diff := fig.center - fig.radius
	return m.vector_length(diff) * game_state.camera.zoom > FIGURE_MIN_RADIUS
}

@(private="file")
vec_rotate :: #force_inline proc "contextless" (v: v2, angle: f32) -> (r: v2) {
	r.x = v.x * m.cos(angle) - v.y * m.sin(angle)
	r.y = v.x * m.sin(angle) + v.y * m.cos(angle)
	return
}

@(private="file")
update_figure_frecuency :: #force_inline proc "contextless" (fig: ^Regular_Figure) {
	// Primero: calcular el lado de la figura.
	//
	// Se forma un triángulo entre el fig.center y de sus 2 vértices, en el que
	// uno de sus lados es también un lado de la figura.
	//
	// Si sacamos una perpendicular de ese lado que pase por el centro,
	// dividimos este triángulo en 2, creando otro triángulo rectángulo con
	// los lados la perpendicular, mitad del lado de la figura y el radio
	// (hipotenusa). Por Pitágoras:
	//
	//     perpendicular^2 + (lado/2)^2 = radio^2
	//
	// Sabemos también que el ángulo que se forma entre la perpendicular y el
	// radio es igual a la mitad del ángulo entre dos lados de la figura.
	//
	//    angulo = (2 * pi / fig.n) / 2 = pi / fig.n
	//    perpendicular = radio * cos(angulo)
	//
	// Entonces:
	//
	//    lado^2/4 = radio^2 - perpendicular^2
	//    lado^2/4 = radio^2 - radio^2 * cos(angulo)^2
	//    lado^2/4 = radio^2 * (1 - cos(angulo)^2)
	//    lado^2 = 4 * radio^2 * (1 - cos(angulo)^2)
	//
	// Como son distancias, solo nos interesa la solución positiva:
	//
	//    lado = sqrt( 4 * radio^2 * (1 - cos(angulo)^2) )
	//    lado = 2 * radio * sqrt(1 - cos(angulo)^2)
	//
	// Sabiendo que: sen(x)^2 + cos(x)^2 = 1 ==> sen(x)^2 = 1 - cos(x)^2
	//
	//    lado = 2 * radio * sqrt(sen(angulo)^2)
	//    lado = 2 * radio * sen(angulo)
	//
	// Lo que tiene bastante sentido porque viendo el triángulo:
	//
	//    lado/2 = radio * sen(angulo)
	//
	// Y directamente sacas que:
	//
	//    lado = 2 * radio * sen(angulo)
	//
	// Bueno, son las 3am, no lo había visto antes...
	radius := m.vector_length(fig.center - fig.radius)
	side := 2 * radius * m.sin(m.PI / f32(fig.n))

	// Segundo: calcular la frecuencia.
	//
	// Empezamos con el período: ¿cuánto tarda en recorrer el lado?
	//
	//    lado (px) / velocidad (px/s) = período (s)
	//
	// Con el período, es trivial conocer la frecuencia:
	//
	//    período (s) = 1 / frecuencia (1/s)
	//    frecuencia (1/s) = 1 / período (s)
	//
	// Entonces:
	//
	//    frecuencia = 1 / período
	//    frecuencia = 1 / (lado / velocidad)
	//    frecuencia = velocidad / lado
	//
	// Si se desea conocer los BPM, se puede hacer con un sencillo factor de
	// conversión:
	//
	//    frecuencia (1/s) * 60 s / 1 min = BPM (1/min)
	//
	fig.frecuency = m.clamp(POINT_SPEED / side, FIGURE_MIN_FRECUENCY, FIGURE_MAX_FRECUENCY)
}

// Operación inversa de la función anterior: usa su campo de frecuencia para
// determinar qué radio tendría que tener
update_figure_radius :: #force_inline proc "contextless" (fig: ^Regular_Figure) {
	side :=  POINT_SPEED / m.clamp(fig.frecuency, FIGURE_MIN_FRECUENCY, FIGURE_MAX_FRECUENCY)

	// Teníamos de antes:
	//
	//    lado = 2 * radio * sen(angulo)
	//    radio = lado / (2 * sen(angulo))
	//
	// Cuidado con:
	//
	//    1 - cos(angulo)^2 = 0
	//    cos(angulo)^2 = 1
	//    cos(angulo) = +/- 1
	//    ==> angulo = 0 + 2 * pi * k,  \forall k \in \RR
	//
	// Pero con angulo = pi / fig.n != 0, entonces no hay problema
	//
	// La forma completa:
	//
	//    radio^2 = perpendicular^2 + (lado/2)^2
	//    radio^2 = (radio * cos(angulo))^2 + lado^2 / 4
	//    radio^2 - radio^2 * cos(angulo)^2 = lado^2 / 4
	//    radio^2 * (1 - cos(angulo)^2) = lado^2 / 4
	//    radio^2 = (lado^2 / 4) / (1 - cos(angulo)^2)
	//    radio = sqrt( (lado^2 / 4) / (1 - cos(angulo)^2) )
	//    radio = lado/2 * sqrt( 1 / (1 - cos(angulo)^2) )
	//    radio = lado/2 * sqrt( 1 / (sen(angulo)^2) )
	//    radio = lado/2 * 1 / sen(angulo)
	//    radio = lado / (2 * sen(angulo))
	//
	radius := side / (2 * m.sin(m.PI / f32(fig.n)))
	// Ahora calcular un nuevo fig.radius que mantenga la misma orientación y
	// cumpla:
	//
	//    m.vector_length(fig.center - fig.radius) = radius
	//
	// Para ello, tomar un vector unitario con el mismo sentido y orientación y
	// escalarlo para que tenga justo ese radio.
	diff := m.normalize0(fig.center - fig.radius)
	fig.radius = fig.center - diff * radius
}
