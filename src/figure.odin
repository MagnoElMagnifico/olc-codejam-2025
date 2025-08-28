package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"
import m "core:math/linalg"

import "core:c"
import "core:mem"
import "core:log"
import "core:slice/heap"

// ==== CONSTANTS =============================================================

FIGURE_MAX_SIDES     :: 25
FIGURE_POINT_RADIUS  :: 5.0
FIGURE_MIN_RADIUS    :: 35
FIGURE_SELECTOR_SIZE :: 20

FIGURE_VIEW_COLOR        :: rl.WHITE
FIGURE_BEAT_COLOR        :: rl.SKYBLUE
FIGURE_FIRST_POINT_COLOR :: rl.GREEN
FIGURE_SELECTED_COLOR    :: rl.RED

SELECTION_RECT_COLOR :: rl.Color { 100, 100, 100, 100 }
LINK_ARROW_HEAD_LEN :: 15.0

// ==== FIGURE DATA ===========================================================

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,
	bpm: uint,
	color_fig: rl.Color,

	// Para los enlaces
	next_figure: ^Regular_Figure,
	previous_figure: ^Regular_Figure,

	// Indica en qué segmento está el punto: [0, n-1]
	point_seg_index: uint,
	// Indica el progreso dentro del segmento actual
	point_progress: f32,
	// Indica el número de ciclos que le queda a la figura (infinito es -1)
	point_counter: int,
	// Indica el contador inicial de la figura (para saber a qué valor resetear)
	point_counter_start: int,

	notes: [FIGURE_MAX_SIDES]Music_Notes,
}

// ==== INPUT UPDATE ==========================================================

// WARN: Solo poner código relacionado con el ratón, no eventos de teclado
// WARN: Los chequeos de colisiones con el ratón se deben hacer en screen space
update_figure_selection_tool :: proc() {
	using game_state

	// Ignorar eventos mientras se está en la UI
	if state != .Move_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) {
		return
	}

	if state == .Selected_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_figure_panel_dim) {
		return
	}

	// Como se puede saltar a este modo desde cualquier otro, poner esto aquí
	if rl.IsMouseButtonPressed(.RIGHT) {
		state = .Rectangle_Multiselection
		current_figure = nil

		// TODO: Si se presiona shift se extiende la selección
		// El problema es que habría que comprobar que no añadir duplicados,
		// cosa que lo hace más lento todavía
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

				center := to_world(game_state.camera, rl.GetMousePosition())

				append(&figures, Regular_Figure {
					center = center,
					radius = center,
					n = create_figure_ui.n_sides,
					point_seg_index = 0,
					point_progress = 0,
					point_counter_start = create_figure_ui.counter,
					point_counter = create_figure_ui.counter,
					bpm = 60
				})

				current_figure = &figures[len(figures)-1]
			}
		}
	}

	case .Edit_Figure: {
		assert(current_figure != nil && len(selected_figures) == 0, "Modo .New_Figure requiere una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			// TODO: para que sean números enteros, aquí hay que hacer
			// cálculos para que coincida bien
			current_figure.radius = to_world(camera, rl.GetMousePosition())

		} else if !is_figure_big_enough(current_figure^) {
			// Si la figura es muy pequeña, salir
			// NOTE: se puede venir aquí si se selecciona una existente y se
			// cambia de tamaño, por lo que esto puede que no lo queramos
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
					// TODO: debería estar vacía realmente
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
			mouse := rl.GetMousePosition()
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
				base.x, base.y, size.x, size.y
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
	// Esta herramienta solo funciona al hacer click
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}

	selected := select_figure()

	// Si se hizo click en otro lado, cancelar la selección
	if select_figure == nil {
		game_state.current_figure = nil
		return
	}

	// Almacenar figura seleccionada para crear el siguiente link
	if game_state.current_figure == nil {
		game_state.current_figure = selected
		return
	}

	// Borrar el link si se hace consigo misma
	if selected == game_state.current_figure {
		// Borrar el link con la siguiente figura
		next := game_state.current_figure.next_figure
		if next == nil do return
		game_state.current_figure.next_figure = nil

		// Borrar el backlink anterior
		next.previous_figure = nil

		// Y cancelar la selección
		game_state.current_figure = nil
		return
	}

	// Crear el enlace con la nueva figura
	game_state.current_figure.next_figure = selected

	// Crear el backlink
	selected.previous_figure = game_state.current_figure

	// Y cancelar la selección
	game_state.current_figure = nil
}

// ==== STATE UPDATE ==========================================================

update_figure_state :: proc(fig: ^Regular_Figure) {
	// No procesar figuras que no tienen contador o que tienen un link hacia
	// ellas y su anterior no terminó aún
	if fig.point_counter == 0 ||
		(fig.previous_figure != nil && fig.previous_figure.point_counter != 0) {
		return
	}

	//
	//     rl.GetFrameTime()
	//
	// Con esto se hace que todos los lados tarden en recorrerse aproximadamente
	// un segundo (poco a poco va atrasando).
	//
	//     rl.GetFrameTime() * f32(fig.n)
	//
	// Lo anterior hace que cada ciclo dure ~1 segundo, por lo que a más
	// vértices, mayor es la frecuencia. Esto también podría ser útil. El
	// problema es que atrasa más rápido.
	//
	// Funciones de Odin con precisión de nanosegundos:
	//
	//     import core:time
	//     time.now() -> Time
	//     time.since(Time) -> Duration
	//
	// TODO: este método de interpolación provoca que todos los segmentos duren
	// lo mismo. Puede que sea lo que queramos, y así evitamos tener que el
	// usuario tenga que medir de forma precisa el perímetro o los lados
	// Posible alternativa, calcular la longitud del lado y:
	//     "tamaño de lado" (px) / "tiempo de frame" (seg) = velocidad
	//
	// TODO: Leer https://www.gamedeveloper.com/audio/coding-to-the-beat---under-the-hood-of-a-rhythm-game-in-unity
	fig.point_progress += rl.GetFrameTime() * f32(fig.bpm) / 60

	// Cambiar de vértice
	if fig.point_progress > 1.0 {
		sound_to_play := game_state.music_notes[fig.notes[Music_Notes(fig.point_seg_index)]]
		rl.SetSoundVolume(sound_to_play, f32(game_state.volume/10))
		rl.PlaySound(sound_to_play)
		fig.point_progress = 0.0
		fig.point_seg_index += 1

		// Nuevo ciclo
		if fig.point_seg_index == fig.n {
			fig.point_seg_index = 0
			if fig.point_counter > 0 do fig.point_counter -= 1
		}
	}
}

// ==== RENDER ================================================================

@(private="file")
render_regular_figure_common :: proc(fig: Regular_Figure, color, point_color: rl.Color) {
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

	if fig.n == 2 {
		// TODO: dibujar hasta y desde el círculo central, pero no atravesarlo
		point1 := to_screen(camera, fig.center + diff)
		point2 := to_screen(camera, fig.center - diff)

		rl.DrawLine(
			c.int(point1.x), c.int(point1.y),
			c.int(point2.x), c.int(point2.y),
			color
		)
	} else {
		rotation := m.atan(diff.y / diff.x) * m.DEG_PER_RAD

		// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
		if diff.x >= 0 do rotation += 180

		rl.DrawPolyLines(
			center = screen_center,
			sides = c.int(fig.n),
			radius = screen_radius,
			rotation = rotation,
			color = color,
		)
	}

	if screen_radius > FIGURE_MIN_RADIUS {
		// Dibujar el "handle" que permite seleccionar y mover la figura
		c_screen_center := iv2 {c.int(screen_center.x), c.int(screen_center.y)}
		rl.DrawCircleLines(c_screen_center.x, c_screen_center.y, FIGURE_SELECTOR_SIZE, color)

		// Dibujar el contador
		counter_str := cstr_from_int(fig.point_counter)
		text_width := rl.MeasureText(counter_str, UI_FONT_SIZE)
		c_screen_center.x -= text_width/2
		c_screen_center.y -= UI_FONT_SIZE/2

		rl.DrawText(
			counter_str,
			c_screen_center.x, c_screen_center.y,
			UI_FONT_SIZE,
			color
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

		rl.DrawLine(
			c.int(start.x), c.int(start.y),
			c.int(end.x), c.int(end.y),
			color
		)
		rl.DrawLine(
			c.int(end.x), c.int(end.y),
			c.int(arrow1.x), c.int(arrow1.y),
			color
		)
		rl.DrawLine(
			c.int(end.x), c.int(end.y),
			c.int(arrow2.x), c.int(arrow2.y),
			color
		)
	}
}

render_regular_figure :: proc(fig: Regular_Figure, color: rl.Color, point_color := FIGURE_BEAT_COLOR, fade := true) {
	using game_state

	// Los parámetros son inmutables por defecto, pero con lo siguiente sí puedo
	// modificarlos
	color := color
	point_color := point_color

	// Cambiar los colores en función del contador
	if fade && fig.point_counter == 0 {
		color = {
			u8(f32(color.r) * 0.6),
			u8(f32(color.b) * 0.6),
			u8(f32(color.g) * 0.6),
			color.a,
		}
		point_color = color
	}

	render_regular_figure_common(fig, color, point_color)
}

render_selected_figure :: proc(fig: Regular_Figure, color: rl.Color) {
	using game_state

	render_regular_figure_common(fig, color, color)

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
		"para borrar una figura, esta debe estar seleccionada"
	)

	// Mueve el último elemento al actual y reduce la longitud
	index := mem.ptr_sub(current_figure, &figures[0])
	unordered_remove(&figures, index)

	state = .View
	current_figure = nil
}

delete_multiselected_figures :: proc() {
	using game_state
	assert(
		current_figure == nil && state == .Multiselection,
		"No está en modo Multiselect"
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
	for i in 0 ..< len(selected_figures) {
		unordered_remove(&figures, indices[0])
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
	screen_center := to_screen(game_state.camera, fig.center)
	screen_radius := to_screen(game_state.camera, fig.radius)
	return m.vector_length2(screen_center - screen_radius) > FIGURE_MIN_RADIUS * FIGURE_MIN_RADIUS
}

@(private="file")
vec_rotate :: #force_inline proc "contextless" (v: v2, angle: f32) -> (r: v2) {
	r.x = v.x * m.cos(angle) - v.y * m.sin(angle)
	r.y = v.x * m.sin(angle) + v.y * m.cos(angle)
	return
}
