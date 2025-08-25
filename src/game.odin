package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"

import "core:c"
import "core:log"
import "core:math/linalg"
import "core:strconv"
import "core:strings"

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
	update_figure_input()

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
			update_figure_state(&f)
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
