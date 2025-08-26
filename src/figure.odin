package game

import rl "vendor:raylib"
import m "core:math/linalg"

import "core:c"
import "core:log"
import "core:mem"

FIGURE_SELECTOR_SIZE       :: 10
FIGURE_MIN_RADIUS_SELECTOR :: 20
FIGURE_MIN_RADIUS          :: 3.0
FIGURE_POINT_RADIUS        :: 5.0
FIGURE_SELECTED_COLOR      :: rl.RED
FIGURE_BEAT_COLOR          :: rl.SKYBLUE
FIGURE_FIRST_POINT_COLOR   :: rl.GREEN

Selection_State :: enum {
	View = 0,
	Edit_Figure,
	Selected_Figure,
	Move_Figure,
}

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,

	// Indica en qué segmento está el punto: [0, n-1]
	point_seg_index: uint,
	// Indica el progreso dentro del segmento actual
	point_progress: f32,
	// Indica el número de ciclos que le queda a la figura (infinito es -1)
	point_counter: int,
	point_counter_start: int,

	notes: [25]Music_Notes,
}

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

// WARN: Solo poner código relacionado con el ratón, no eventos de teclado
update_figure_mouse_input :: proc() {
	using game_state

	// Ignorar eventos mientras se está en la UI
	if state != .Move_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) {
		return
	}

	if state == .Selected_Figure && rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_figure_panel_dim) {
		return
	}

	switch state {
	case .View: {
		assert(current_figure == nil, "En modo .View, current_figure debe ser nil")

		if rl.IsMouseButtonPressed(.LEFT) {
			// Comprobar si se seleccionan figuras
			mouse_world := to_world(camera, rl.GetMousePosition())
			for &fig in figures {
				// Esta comprobación es rápida, por eso usamos círculos
				if rl.CheckCollisionPointCircle(mouse_world, fig.center, FIGURE_SELECTOR_SIZE) {
					current_figure = &fig
					break
				}
			}
			
			if current_figure != nil {
				// Seleccionar figura
				log.info("Figura seleccionada")
				state = .Selected_Figure

			} else {
				// Crear nueva figura
				log.info("Creación de una figura")
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
				})

				current_figure = &figures[len(figures)-1]
			}
		}
	}

	case .Edit_Figure: {
		assert(current_figure != nil, "Modo .New_Figure require una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			// TODO: para que sean números enteros, aquí hay que hacer
			// cálculos para que coincida bien
			current_figure.radius = to_world(camera, rl.GetMousePosition())
		} else if m.vector_length(current_figure.center - current_figure.radius) < FIGURE_MIN_RADIUS {
			// Si la figura es muy pequeña, salir
			// NOTE: se puede venir aquí si se selecciona una existente y se
			// cambia de tamaño, por lo que esto puede que no lo queramos
			current_figure = nil
			state = .View
			pop(&figures)
		} else {
			log.info("Figura creada en", current_figure.center)
			state = .Selected_Figure
		}
	}

	case .Selected_Figure: {
		assert(current_figure != nil, "Modo .Selected_Figure require una figura seleccionada")

		if rl.IsMouseButtonPressed(.LEFT) {
			// Comprobar si seleccionamos algo
			mouse_world := to_world(camera, rl.GetMousePosition())

			// Comprobar si se hace click en el vértice para cambiar su tamaño
			if rl.CheckCollisionPointCircle(mouse_world, current_figure.radius, FIGURE_POINT_RADIUS) {
				log.info("Cambiar tamaño de figura")
				state = .Edit_Figure

			} else {
				// Sino, mirar si se ha seleccionado otra figura
				new_selected_figure: ^Regular_Figure
				for &fig in figures {
					// Esta comprobación es rápida, por eso usamos círculos
					if rl.CheckCollisionPointCircle(mouse_world, fig.center, FIGURE_SELECTOR_SIZE) {
						new_selected_figure = &fig
					}
				}

				if new_selected_figure == nil {
					// Deseleccionar si se hace click en otro lado
					current_figure = nil
					state = .View
				} else if new_selected_figure == current_figure {
					// Arrastrar la figura
					state = .Move_Figure
				} else {
					// Seleccionar otra figura
					current_figure = new_selected_figure
				}
			}
		}

		// TODO: cambiar tamaño / lado / perímetro
	}

	case .Move_Figure: {
		assert(current_figure != nil, "Modo .Move_Figure require una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			diff := current_figure.center - current_figure.radius
			current_figure.center = to_world(camera, rl.GetMousePosition())
			current_figure.radius = current_figure.center - diff
		} else {
			state = .Selected_Figure
		}
	}
	}
}


update_figure_state :: proc(fig: ^Regular_Figure) {
	// No procesar figuras que no tienen contador
	if fig.point_counter == 0 {
		return
	}

	// TODO: este método de interpolación provoca que todos los segmentos duren
	// lo mismo. Puede que sea lo que queramos, y así evitamos tener que el
	// usuario tenga que medir de forma precisa el perímetro o los lados
	// Posible alternativa, calcular la longitud del lado y:
	//     "tamaño de lado" (px) / "tiempo de frame" (seg) = velocidad
	fig.point_progress += rl.GetFrameTime()

	// Cambiar de vértice
	if fig.point_progress > 1.0 {
		rl.PlaySound(game_state.music_notes[.Do])
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

	if screen_radius > FIGURE_MIN_RADIUS_SELECTOR {
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

		point1: v2
		point1.x = fig.center.x - (diff.x * m.cos(angle1) - diff.y * m.sin(angle1))
		point1.y = fig.center.y - (diff.x * m.sin(angle1) + diff.y * m.cos(angle1))

		point2: v2
		point2.x = fig.center.x - (diff.x * m.cos(angle2) - diff.y * m.sin(angle2))
		point2.y = fig.center.y - (diff.x * m.sin(angle2) + diff.y * m.cos(angle2))

		// Ahora interpolar entre las dos posiciones
		// Ecuación vectorial de una recta: (x, y) = p1 + k * v
		line_vector := point2 - point1
		beat_point := point1 + fig.point_progress * line_vector
		beat_point = to_screen(camera, beat_point)

		rl.DrawCircle(c.int(beat_point.x), c.int(beat_point.y), FIGURE_POINT_RADIUS, point_color)
	}
}

render_regular_figure :: proc(fig: Regular_Figure, color: rl.Color, point_color := FIGURE_BEAT_COLOR) {
	using game_state

	// Los parámetros son inmutables por defecto, pero con lo siguiente sí puedo
	// modificarlos
	color := color
	point_color := point_color

	// Cambiar los colores en función del contador
	if fig.point_counter == 0 {
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

