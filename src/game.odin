package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"
import "core:c"
import "core:log"

// ==== CONSTANTS =============================================================

// Definiciones de tipos comunes (por comodidad)
iv2 :: [2]c.int
v2 :: rl.Vector2     // [2]f32
rect :: rl.Rectangle // { x, y, width, height: f32 }

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop
	simulation_running: bool, // Determina si mover los puntos de las figuras

	figures: [dynamic]Regular_Figure,

	// Determinar qué hacen las acciones del ratón
	state: Selection_State,
	// nil: nada seleccionado
	current_figure: ^Regular_Figure,
	sync_points: bool,

	ui: UI_State,
	camera: Camera,
	window_size: iv2,
	music_notes: [9]rl.Sound
}

// ==== GAME INIT =============================================================

import "core:os"

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
	rl.InitAudioDevice()

	//TODO: La apertura del archivo falla. Pero teóricamente el path es correcto.
	game_state.music_notes[0] = rl.LoadSound("/src/sounds/Do.wav")
	game_state.music_notes[1] = rl.LoadSound("/src/sounds/Re.wav")
	game_state.music_notes[2] = rl.LoadSound("/src/sounds/Mi.wav")
	game_state.music_notes[3] = rl.LoadSound("/src/sounds/Fa.wav")
	game_state.music_notes[4] = rl.LoadSound("/src/sounds/Sol.wav")
	game_state.music_notes[5] = rl.LoadSound("/src/sounds/La.wav")
	game_state.music_notes[6] = rl.LoadSound("/src/sounds/Si.wav")
	game_state.music_notes[7] = rl.LoadSound("/src/sounds/Do'.wav")
	game_state.music_notes[8] = rl.LoadSound("/src/sounds/Re'.wav")

	log.info(os.args[0])

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

	if game_state.sync_points {
		if game_state.state == .New_Figure || game_state.state == .Selected_Figure || game_state.state == .Move_Figure {
			//Resetear solo la seleccionada
			reset_figure_state(game_state.current_figure)
		}else{
			//Si ninguna está seleccionada, resetea todas
			for &f in game_state.figures {
				reset_figure_state(&f)
			}
		}
		game_state.sync_points = false
	}

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
	for music_note in game_state.music_notes {
		rl.UnloadSound(music_note)
	}
	rl.CloseAudioDevice()
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
