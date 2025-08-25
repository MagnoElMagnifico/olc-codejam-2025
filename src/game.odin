package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"

import "core:math/linalg"
import "core:log"
import "core:c"
import "core:strconv"
import "core:strings"
import "core:math"

// ==== CONSTANTS =============================================================

// Definiciones de tipos comunes (por comodidad)
iv2 :: [2]c.int
v2 :: rl.Vector2     // [2]f32
rect :: rl.Rectangle // { x, y, width, height: f32 }

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}

MIN_FIG_RADIUS :: 3.0

FIGURE_SELECTOR_SIZE :: 10
FIGURE_MIN_RADIUS_SELECTOR :: 20

CAMERA_ZOOM_SPEED :: 0.25
CAMERA_ZOOM_MIN :: 0.25
CAMERA_ZOOM_MAX :: 3.0

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop
	simulation_running: bool, // Determina si mover los puntos de las figuras

	figures: [dynamic]Regular_Figure,

	// Determinar qué hacen las acciones del ratón
	state: State,
	// nil: nada seleccionado
	current_figure: ^Regular_Figure,

	ui: UI_State,
	camera: Camera,
	window_size: iv2
}

Camera :: struct {
	zoom: f32,
	position: v2,

	// Para mover la cámara, se almacena la posición antes de moverse y luego se
	// actualiza el offset.
	// Estas coordenadas están en screen space.
	start_pos: v2,
	offset: v2,
}

State :: enum {
	View = 0,
	New_Figure,
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
	// Indica el número de ciclos que le queda a la figura
	// TODO: cómo representamos infinito?
	// point_counter: uint,
}

// ==== CAMERA STUFF ==========================================================

// Convierte un vector con coordenadas del mundo a coordenadas de pantalla
// Usar siempre antes de dibujar algo en la pantalla para que la camara funcione
// correctamente.
to_screen :: proc(camera: Camera, v: v2) -> v2 {
	// El centro del zoom será el centro de la pantalla
	focus := v2 { f32(game_state.window_size.x) / 2, f32(game_state.window_size.y) / 2 }

	// https://rexthony.medium.com/how-panning-and-zooming-work-in-a-2d-top-down-game-ab00c9d05d1a
	pan := v - camera.position - camera.offset
	zoom := camera.zoom * pan - focus * (camera.zoom - 1)

	return zoom
}

// Convierte un vector con coordenadas la pantalla (posición del ratón) a
// coordenadas de mundo
to_world :: proc(camera: Camera, v: v2) -> v2 {
	focus := v2 { f32(game_state.window_size.x) / 2, f32(game_state.window_size.y) / 2 }
	// v = z * pan - focus * (z - 1)
	// v / z = pan - focus * (z - 1) / z
	// pan = v / z + focus * (z - 1) / z
	// pan = (v + focus * (z - 1)) / z

	undo_zoom := (v + focus * (camera.zoom - 1)) / camera.zoom
	undo_pan := undo_zoom + camera.position + camera.offset
	return undo_pan
}

update_camera :: proc() {
	using game_state.camera
	// ==== Camera movement ====
	if rl.IsMouseButtonPressed(.MIDDLE) {
		start_pos = rl.GetMousePosition()
	}

	if rl.IsMouseButtonDown(.MIDDLE) {
		offset = (start_pos - rl.GetMousePosition()) / zoom
	}

	if rl.IsMouseButtonReleased(.MIDDLE) {
		position += offset
		offset = {}
	}

	// ==== Camera zoom ====
	mouse_wheel := rl.GetMouseWheelMove()
	if mouse_wheel != 0 {
		zoom = linalg.clamp(zoom + mouse_wheel * CAMERA_ZOOM_SPEED, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	}
}

// ==== FIGURES ===============================================================

render_regular_figure :: proc(fig: Regular_Figure, color: rl.Color) {
	diff := fig.center - fig.radius
	rotation := linalg.atan(diff.y / diff.x) * linalg.DEG_PER_RAD

	// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
	if diff.x > 0 do rotation += 180

	// Transformar coordenadas del mundo a coordenadas en la pantalla
	using game_state
	screen_center := to_screen(camera, fig.center)
	screen_radius := linalg.vector_length(diff) * camera.zoom

	rl.DrawPolyLines(
		center = screen_center,
		sides = c.int(fig.n),
		radius = screen_radius,
		rotation = rotation,
		color = color,
	)

	if screen_radius > FIGURE_MIN_RADIUS_SELECTOR {
		rl.DrawCircleLines(c.int(screen_center.x), c.int(screen_center.y), FIGURE_SELECTOR_SIZE, color)
	}

	// Dibujar los vértices
	// El siguiente es equivalente, pero menos código: for i := 0; i < int(n); i += 1
	//
	// TODO: probablemente se pueda calcular de otra forma más eficiente, pero
	// por ahora así nos sirve.
	//
	// Todas las figuras regulares tienen los mismos ángulos, lo que implica que
	// podemos calcular así solo 2 puntos, tomar su vector y sumarlo N-1 veces
	// para encontrar el resto de puntos. Así es más rápido porque para los dos
	// primeros calculas varios (sen, cos), pero para el resto son solo sumas.
	//
	// Sin embargo, no sé si en el resultado final tendremos que dibujar los
	// vértices.
	when false {
		for i in 0 ..< fig.n {
			angle := math.to_radians(360 * f32(i) / f32(fig.n))

			circle_center: v2
			circle_center.x = fig.center.x - (diff.x * math.cos(angle) - diff.y * math.sin(angle))
			circle_center.y = fig.center.y - (diff.x * math.sin(angle) + diff.y * math.cos(angle))
			circle_center = to_screen(camera, circle_center)

			rl.DrawCircleLines(c.int(circle_center.x), c.int(circle_center.y), 5.0, color)
		}
	}

	// Dibujar el punto
	/*if fig.point_counter > 0*/ {
		// Calcular puntos del segmento actual: igual que en el bucle
		angle1 := math.to_radians(360 * f32(fig.point_seg_index)     / f32(fig.n))
		angle2 := math.to_radians(360 * f32(fig.point_seg_index + 1) / f32(fig.n))

		point1: v2
		point1.x = fig.center.x - (diff.x * math.cos(angle1) - diff.y * math.sin(angle1))
		point1.y = fig.center.y - (diff.x * math.sin(angle1) + diff.y * math.cos(angle1))

		point2: v2
		point2.x = fig.center.x - (diff.x * math.cos(angle2) - diff.y * math.sin(angle2))
		point2.y = fig.center.y - (diff.x * math.sin(angle2) + diff.y * math.cos(angle2))

		// Ahora interpolar entre las dos posiciones
		// Ecuación vectorial de una recta: (x, y) = p1 + k * v
		// TODO: este método de interpolación provoca que todos los segmentos duren
		// lo mismo. Puede que sea lo que queramos, y así evitamos tener que el
		// usuario tenga que medir de forma precisa el perímetro o los lados
		line_vector := point2 - point1
		beat_point := point1 + fig.point_progress * line_vector
		beat_point = to_screen(camera, beat_point)

		rl.DrawCircle(c.int(beat_point.x), c.int(beat_point.y), 5.0, rl.SKYBLUE)
	}
}

update_regular_figure :: proc(fig: ^Regular_Figure) {
	// No procesar figuras que no tienen contador
	/*if fig.point_counter <= 0 {
		return
	}*/

	// TODO: hacer bien el deltatime, ya que esta aplicación requiere de un
	// ritmo bastante preciso: https://youtu.be/yGhfUcPjXuE
	fig.point_progress += rl.GetFrameTime()

	if fig.point_progress > 1.0 {
		// TODO: el sonido se reproduce aquí, porque sabemos que acaba de
		// cambiar de segmento
		fig.point_progress = 0.0
		fig.point_seg_index = (fig.point_seg_index + 1) % (fig.n)
		// fig.point_counter -= 1
	}
}

update_mouse_input :: proc() {
	// Ignorar eventos mientras se está en la UI
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) {
		return
	}

	using game_state
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
				state = .New_Figure

				center := to_world(game_state.camera, rl.GetMousePosition())
				append(&figures, Regular_Figure {
					center = center,
					radius = center,
					n = ui.n_sides,
				})

				current_figure = &figures[len(figures)-1]
			}
		}
	}

	case .New_Figure: {
		assert(current_figure != nil, "Modo .New_Figure require una figura seleccionada")

		if rl.IsMouseButtonDown(.LEFT) {
			// TODO: para que sean números enteros, aquí hay que hacer
			// cálculos para que coincida bien
			current_figure.radius = to_world(camera, rl.GetMousePosition())
		} else if linalg.vector_length(current_figure.center - current_figure.radius) < MIN_FIG_RADIUS {
			// Si la figura es muy pequeña, salir
			current_figure = nil
			state = .View
			pop(&figures)
		} else {
			// De lo contrario, añadir a la lista
			log.info("Figura creada en", current_figure.center)
			state = .Selected_Figure
		}
	}

	case .Selected_Figure: {
		assert(current_figure != nil, "Modo .Selected_Figure require una figura seleccionada")

		if rl.IsKeyPressed(.ESCAPE) {
			current_figure = nil
			state = .View
		}

		if rl.IsMouseButtonPressed(.LEFT) {
			mouse_world := to_world(camera, rl.GetMousePosition())
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

	// Actualizar UI tras los cambios de estado
	if state == .Selected_Figure {
		// Actualizar UI con su numero de lados
		ui.n_sides = current_figure.n
		set_text_to_number(ui.sides_text[:], ui.n_sides)
	}

}

// ==== GAME INIT =============================================================

init :: proc() {
	using game_state

	run = true
	simulation_running = true
	camera.zoom = 1.0
	ui.n_sides = 3
	window_size = WINDOW_SIZE
	set_text_to_number(ui.sides_text[:], ui.n_sides)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(window_size.x, window_size.y, WINDOW_NAME)

	// No cerrar en escape
	rl.SetExitKey(.KEY_NULL)
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// Llamar también en desktop para actualizar el valor del game_state
	when ODIN_OS != .JS {
		parent_window_size_changed(rl.GetScreenWidth(), rl.GetScreenHeight())
	}

	// ==== Game input handling ===============================================
	update_camera()
	update_mouse_input()

	if rl.IsKeyPressed(.SPACE) {
		game_state.simulation_running = !game_state.simulation_running
	}

	// ==== Render ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({30, 30, 30, 255})

	// Render todas las figuras
	for &f in game_state.figures {
		// PERF: quizá mover el if a su propio bucle, pero el branch predictor
		// lo detectará bien porque es constante
		if game_state.simulation_running {
			update_regular_figure(&f)
		}
		render_regular_figure(f, rl.WHITE)
	}

	// Render la figura seleccionada en un color distinto
	if game_state.state == .New_Figure || game_state.state == .Selected_Figure || game_state.state == .Move_Figure {
		// TODO: se dibujará 2 veces la figura seleccionada
		render_regular_figure(game_state.current_figure^, rl.RED)
	}

	// Render UI: debe ejecutarse después de las figuras para que se muestre por
	// encima.
	render_ui()

	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove
// the `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: c.int) {
	game_state.window_size = {w, h}
	when ODIN_OS == .JS {
		// No ejecutar en desktop porque lo leemos desde la propia ventana
		rl.SetWindowSize(w, h)
	}
}

shutdown :: proc() {
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			game_state.run = false
		}
	}

	return game_state.run
}
