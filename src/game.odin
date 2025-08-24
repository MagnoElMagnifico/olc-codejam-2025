package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"

import "core:math/linalg"
import "core:log"
import "core:fmt"
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

UI_PADDING     : f32 : 3
UI_LINE_HEIGHT : f32 : 30
UI_MARGIN      :     : 10
UI_Y_POS       :     : 20 + UI_MARGIN

// Tamaño del panel UI
UI_PANEL_DIM :: rect {
	UI_MARGIN,
	UI_MARGIN,
	/* text: */ 100 + /* 2 botones: */ 2*UI_LINE_HEIGHT + 3*UI_PADDING,
	2 * UI_LINE_HEIGHT
}

CAMERA_ZOOM_SPEED :: 0.25
CAMERA_ZOOM_MIN :: 0.25
CAMERA_ZOOM_MAX :: 3.0

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop
	simulation_running: bool, // Determina si mover los puntos de las figuras

	state: State,
	figures: [dynamic]Regular_Figure,
	current_figure: Regular_Figure,

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

UI_State :: struct {
	n_sides: uint,
	// solo hacen falta dos dígitos + null terminator
	sides_text: [3]u8,
}

State :: enum {
	View = 0,
	New_Figure,
	Selected_Figure,
}

Vertice :: struct {
	center: v2,
	radius: int,
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
}

// Convertir el numero actual a cstring para mostrarlo en la UI
set_text_to_number :: proc(buf: []u8, n: uint) {
	assert(len(buf) <= 3, "set_text only implemented for 2 digits")

	// Conversión de 1 dígito
	if n < 10 {
		buf[0] = u8(n + uint('0'))
		buf[1] = 0
		return
	}

	// Conversión de 2 dígitos
	buf[0] = u8(n/10 + uint('0'))
	buf[1] = u8(n%10 + uint('0'))
	buf[2] = 0
}

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
	if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
		start_pos = rl.GetMousePosition()
	}

	if rl.IsMouseButtonDown(rl.MouseButton.MIDDLE) {
		offset = (start_pos - rl.GetMousePosition()) / zoom
	}

	if rl.IsMouseButtonReleased(rl.MouseButton.MIDDLE) {
		position += offset
		offset = {}
	}

	// ==== Camera zoom ====
	mouse_wheel := rl.GetMouseWheelMove()
	if mouse_wheel != 0 {
		zoom = linalg.clamp(zoom + mouse_wheel * CAMERA_ZOOM_SPEED, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	}
}

render_regular_figure :: proc(fig: Regular_Figure, color: rl.Color) {
	diff := fig.center - fig.radius
	rotation := linalg.atan(diff.y / diff.x) * linalg.DEG_PER_RAD

	// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
	if diff.x > 0 do rotation += 180

	// Transformar coordenadas del mundo a coordenadas en la pantalla
	using game_state
	rl.DrawPolyLines(
		center = to_screen(camera, fig.center),
		sides = c.int(fig.n),
		radius = linalg.vector_length(diff) * camera.zoom,
		rotation = rotation,
		color = color,
	)

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
	for i in 0 ..< fig.n {
		angle := math.to_radians(360 * f32(i) / f32(fig.n))

		circle_center: v2
		circle_center.x = fig.center.x - (diff.x * math.cos(angle) - diff.y * math.sin(angle))
		circle_center.y = fig.center.y - (diff.x * math.sin(angle) + diff.y * math.cos(angle))
		circle_center = to_screen(camera, circle_center)

		rl.DrawCircleLines(c.int(circle_center.x), c.int(circle_center.y), 5.0, color)
	}

	// Dibujar el punto
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

	rl.DrawCircleLines(c.int(beat_point.x), c.int(beat_point.y), 5.0, rl.SKYBLUE)
}

update_regular_figure :: proc(fig: ^Regular_Figure) {
	// TODO: hacer bien el deltatime, ya que esta aplicación requiere de un
	// ritmo bastante preciso: https://youtu.be/yGhfUcPjXuE
	fig.point_progress += rl.GetFrameTime()

	if fig.point_progress > 1.0 {
		// TODO: el sonido se reproduce aquí, porque sabemos que acaba de
		// cambiar de segmento
		fig.point_progress = 0.0
		fig.point_seg_index = (fig.point_seg_index + 1) % (fig.n)
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
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// Llamar también en desktop para actualizar el valor del game_state
	when ODIN_OS != .JS {
		parent_window_size_changed(rl.GetScreenWidth(), rl.GetScreenHeight())
	}

	// ==== GAME INPUT HANDLING ===============================================
	// Máquina de estados
	switch game_state.state {
		case .View: {
			update_camera()

			using game_state

			if !rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				log.info("Creación de una figura")

				current_figure.center = to_world(game_state.camera, rl.GetMousePosition())
				current_figure.n = game_state.ui.n_sides

				// Evita que la figura haga flash si solo se hace un click
				current_figure.radius = current_figure.center

				state = .New_Figure
			}

			if rl.IsKeyPressed(.SPACE) {
				simulation_running = !simulation_running
			}

			// TODO: transición a .Selected_Figure
		}

		case .New_Figure: {
			using game_state.current_figure

			if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
				// TODO: para que sean números enteros, aquí hay que hacer
				// cálculos para que coincida bien
				radius = to_world(game_state.camera, rl.GetMousePosition())
			} \

			// Si la figura es muy pequeña, salir
			else if linalg.vector_length(center - radius) < MIN_FIG_RADIUS {
				game_state.state = .View
			} \

			// De lo contrario, añadir a la lista
			else {
				append(&game_state.figures, game_state.current_figure)
				log.info("Figura creada en", game_state.current_figure.center)
				game_state.state = .View
			}
		}

		case .Selected_Figure: {
			// TODO:
		}
	}

	// ==== RENDER ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({30, 30, 30, 255})

	// Render figure
	if game_state.state == .New_Figure {
		render_regular_figure(game_state.current_figure, rl.RED)
	}

	for &f in game_state.figures {
		// PERF: quizá mover el if a su propio bucle, pero el branch predictor
		// lo detectará bien porque es constante
		if game_state.simulation_running {
			update_regular_figure(&f)
		}
		render_regular_figure(f, rl.WHITE)
	}

	// Render UI: debe ejecutarse después de las figuras para que se muestre por
	// encima.
	// TODO: customizar estilos, se ve bastante como la caca
	{
		using game_state.ui

		// Para la UI de más adelante
		current_x : f32 = UI_PADDING + UI_MARGIN // posicion inicial

		panel := UI_PANEL_DIM
		panel.height /= 2
		rl.GuiPanel(panel, "Figure Options")

		rl.GuiLabel({current_x, UI_Y_POS, 30, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, UI_Y_POS, 5, UI_LINE_HEIGHT},
			cstring(raw_data(game_state.ui.sides_text[:])))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, UI_Y_POS+5, UI_LINE_HEIGHT-10, UI_LINE_HEIGHT-10}, "+") {
			n_sides = min(n_sides + 1, 25)
			set_text_to_number(sides_text[:], n_sides)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, UI_Y_POS+5, UI_LINE_HEIGHT-10, UI_LINE_HEIGHT-10}, "-") {
			// TODO: permitir líneas? Habría un salto de 2 a 1 (no hay figuras de 2 lados
			n_sides = max(n_sides - 1, 3)
			set_text_to_number(sides_text[:], n_sides)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	// Debug info
	{
		rl.DrawText(
			fmt.caprintf("simulation: %w\x00", game_state.simulation_running, context.temp_allocator),
			0, game_state.window_size.y - 65, 12, rl.WHITE)
		rl.DrawText(
			fmt.caprintf("time: %1.5f\x00", rl.GetFrameTime(), context.temp_allocator),
			0, game_state.window_size.y - 50, 12, rl.WHITE)
		rl.DrawText(
			fmt.caprintf("zoom: %1.5f\x00", game_state.camera.zoom, context.temp_allocator),
			0, game_state.window_size.y - 35, 12, rl.WHITE)
		rl.DrawText(
			fmt.caprintf("n figures: %d\x00", len(game_state.figures), context.temp_allocator),
			0, game_state.window_size.y - 20, 12, rl.WHITE)
	}

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
