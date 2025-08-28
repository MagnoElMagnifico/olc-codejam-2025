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

COLOR_PICKER : [3]u8 = {0,127,255}

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}

Music_Notes :: enum u8 {
	// TODO: Añadir más notas?
	// TODO: hacer Null = 0 para que sea la nota por defecto?
	Do, Re, Mi, Fa, Sol, La, Si, Dop, Rep, Null
}

// Técnicamente una constante. No cambiar :(
STRING_NOTES := [Music_Notes]cstring {
	.Do = "Do",
	.Re = "Re",
	.Mi = "Mi",
	.Fa = "Fa",
	.Sol = "Sol",
	.La = "La",
	.Si = "Si",
	.Dop = "Dop",
	.Rep = "Rep",
	.Null = "---"
}

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	// ==== State ====
	run: bool,                       // Determina si seguir ejecutando el game loop
	simulation_running: bool,        // Determina si mover los puntos de las figuras
	state: Selection_State,          // Determinar qué hacen las acciones del ratón

	// El uso de las siguientes variables depende de `state`
	current_figure: ^Regular_Figure,
	selected_figures: [dynamic]^Regular_Figure,
	selection_rect: rect,
	selection_rect_center: v2,

	// ==== Objects ====
	figures: [dynamic]Regular_Figure,
	camera: Camera,
	create_figure_ui: UI_Create_State,
	volume: f32,

	// ==== Information ====
	window_size: iv2,

	// ==== Resources ====
	music_notes: [Music_Notes]rl.Sound
}

// ==== GAME INIT =============================================================

import "core:os"
import "core:math/rand"

init :: proc() {
	using game_state

	run = true
	simulation_running = true
	camera.zoom = 1.0
	create_figure_ui.n_sides = 3
	create_figure_ui.counter = -1
	window_size = WINDOW_SIZE
	volume = 10

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(window_size.x, window_size.y, WINDOW_NAME)
	rl.InitAudioDevice()

	game_state.music_notes[.Do]  = rl.LoadSound("assets/sounds/Do.wav")
	game_state.music_notes[.Re]  = rl.LoadSound("assets/sounds/Re.wav")
	game_state.music_notes[.Mi]  = rl.LoadSound("assets/sounds/Mi.wav")
	game_state.music_notes[.Fa]  = rl.LoadSound("assets/sounds/Fa.wav")
	game_state.music_notes[.Sol] = rl.LoadSound("assets/sounds/Sol.wav")
	game_state.music_notes[.La]  = rl.LoadSound("assets/sounds/La.wav")
	game_state.music_notes[.Si]  = rl.LoadSound("assets/sounds/Si.wav")
	game_state.music_notes[.Dop] = rl.LoadSound("assets/sounds/Do'.wav")
	game_state.music_notes[.Rep] = rl.LoadSound("assets/sounds/Re'.wav")

	// No cerrar en escape
	rl.SetExitKey(.KEY_NULL)
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// Llamar también en desktop para actualizar el valor del game_state
	when ODIN_OS != .JS {
		parent_window_size_changed(rl.GetScreenWidth(), rl.GetScreenHeight())
	}

	// ==== Input handling ====================================================

	update_camera()
	update_figure_selection()

	if rl.IsKeyPressed(.SPACE) {
		game_state.simulation_running = !game_state.simulation_running
	}

	if rl.IsKeyPressed(.ESCAPE) {
		game_state.current_figure = nil
		clear(&game_state.selected_figures)
		game_state.state = .View
	}

	if rl.IsKeyPressed(.BACKSPACE) && check_backspace_action() == 1 || rl.IsKeyPressed(.DELETE) {
		if game_state.current_figure != nil do delete_current_figure()
		else if game_state.state == .Multiselection do delete_multiselected_figures()
	}


	// ==== Render ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({30, 30, 30, 255})

	for &f in game_state.figures {
		// Esto es mejor que actualizar todo y luego renderizar: solo se
		// recorren todas las figuras una vez. El `if` no importa mucho porque
		// es constante y el branch predictor lo detectará bien.
		if game_state.simulation_running {
			update_figure_state(&f)
		}

				//log.info(game_state.current_figure.color_fig)
		if f.color_fig[3] != 255 {
			//Esta estructura de dato aleatorio es para prevenir que se seleccione un color demasiado oscuro
			stop_random := false
			r : u8 = 0
			g : u8 = 0
			b : u8 = 0
			for !stop_random {
				r = rand.choice(COLOR_PICKER[:])
				g = rand.choice(COLOR_PICKER[:])
				b = rand.choice(COLOR_PICKER[:])
				if r != 0 || b != 0 || g != 0 {
					stop_random = true
				}
			}
			f.color_fig = {r,g,b,255}
		}
		render_regular_figure(f, f.color_fig)
	}

	// Render la figura seleccionada en un color distinto
	// PERF: Se dibujarán 2 veces las figuras seleccionadas
	switch game_state.state {
	case .View: break

	case .Edit_Figure: fallthrough
	case .Selected_Figure: fallthrough
	case .Move_Figure:
		render_selected_figure(game_state.current_figure^, FIGURE_SELECTED_COLOR)
		render_figure_ui()

	case .Multiselection: fallthrough
	case .Multiselection_Move:
		for fig in game_state.selected_figures {
			render_regular_figure(fig^, FIGURE_SELECTED_COLOR, FIGURE_SELECTED_COLOR, false)
		}

	case .Rectangle_Multiselection:
		rl.DrawRectangleRec(game_state.selection_rect, SELECTION_RECT_COLOR)
	}

	// ==== UI ================================================================
	// Debe ejecutarse después de las figuras para que se muestre por encima.
	// Esto puede ser molesto porque el frame ya se ha dibujado, entonces el
	// input de la UI se procesará para el siguiente frame.

	render_create_figure_ui()
	render_debug_info()

	// Borrar memoria temporal
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
