package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"
import "core:c"
import "core:log"
import "core:math/rand"

// Definiciones de tipos comunes (por comodidad)
iv2 :: [2]c.int
v2 :: rl.Vector2     // [2]f32
rect :: rl.Rectangle // { x, y, width, height: f32 }
color :: rl.Color    // [4]u8

// ==== CONSTANTS =============================================================

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}
MAX_FIGURES :: 10 when ODIN_DEBUG else 1024
BACKGROUND_COLOR :: color { 30, 30, 30, 255 }

Music_Notes :: enum u8 {
	Do, Re, Mi, Fa, Sol, La, Si, Dop, Rep, Null,
}

@(rodata)
COLOR_PICKER := [3]u8 {0, 127, 255}

@(rodata)
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
	.Null = "---",
}

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	// ==== State ====
	run: bool,                // Determina si seguir ejecutando el game loop
	simulation_running: bool, // Determina si mover los puntos de las figuras

	tool: Tools,              // Determina qué herramienta se está usando
	state: Selection_State,   // tool == .Select: estado de la selección

	// El uso de las siguientes variables depende de `Selection_State`
	current_figure: ^Regular_Figure,
	selected_figures: [dynamic]^Regular_Figure,
	selection_rect: rect,
	selection_rect_center: v2,

	// ==== Objects ====
	figures: [dynamic]Regular_Figure,
	camera: Camera,
	ui: UI_State,

	// ==== Information ====
	window_size: iv2,

	// ==== Resources ====
	music_notes: [Music_Notes]rl.Sound,
}

Selection_State :: enum {
	View = 0,
	Edit_Figure,
	Selected_Figure,
	Multiselection,
	Rectangle_Multiselection,
	Move_Figure,
	Multiselection_Move,
}

// Al pulsar el número en el teclado, se cambia a esa herramienta
Tools :: enum {
	View = 0,
	Select = 1,
	Link = 2,
}

// ==== GAME INIT =============================================================

init :: proc() {
	using game_state

	run = true
	simulation_running = true
	tool = .Select
	state = .View

	camera.zoom = 1.0
	window_size = WINDOW_SIZE

	// TODO: usar otra fuente
	ui.font = rl.GetFontDefault()
	ui.creation_n_sides = 3
	ui.creation_counter = -1
	ui.volume = 10
	update_ui_dimensions()

	// `game_state.figures` contiene punteros a otros elementos del array, por
	// lo que si se mueven los elementos de un lado para otro al borrar y
	// añadir, tendremos bugs de memoria (se apunta a figuras incorrectas) y
	// crasheos (punteros inválidos).
	//
	// Para arreglarlo, las funciones `delete_current_figure` y
	// `delete_multiselected_figures` gestionan los casos apropiadamente.
	//
	// Pero para añadir nuevas figuras, cuando el buffer actual sea muy pequeño,
	// se copiarán los a un buffer más grande. En tal caso se invalidarán todos
	// los punteros.
	//
	// Una solución es usar los índices de las figuras, ya que no dependen de la
	// posición absoluta en memoria, sino de la distancia al inicio del buffer.
	// Como se copian por orden, no hay problema.
	//
	// Otra opción es mantener los punteros y usar un buffer con una capacidad
	// fija, y así evitar que se copien a otros lugares. Esta es ligeramente más
	// eficiente, porque evita estas copias (que son lentas cuando el buffer es
	// grande), pero tiene un mayor uso de memoria y se impone un límite máximo
	// de figuras.
	figures = make([dynamic]Regular_Figure, 0, MAX_FIGURES)
	log.info("Regular_Figure size:", size_of(Regular_Figure))
	log.info("Total memory for figures:", size_of(Regular_Figure) * MAX_FIGURES)

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

	if rl.IsKeyPressed(.SPACE) {
		game_state.simulation_running = !game_state.simulation_running
	}

	{
		tool_changed := false
		if rl.IsKeyPressed(.ZERO) {
			game_state.tool = .View
			tool_changed = true
		}

		if rl.IsKeyPressed(.ONE) {
			game_state.tool = .Select
			tool_changed = true
		}

		if rl.IsKeyPressed(.TWO) {
			game_state.tool = .Link
			tool_changed = true
		}

		// Limpiar el estado para que no quede corrupto
		if tool_changed {
			game_state.current_figure = nil
			game_state.state = .View
			clear(&game_state.selected_figures)
		}
	}

	// TODO: esto no funciona super bien: aún se pueden crear figuras debajo
	if rl.IsMouseButtonDown(.LEFT) || !rl.CheckCollisionPointRec(rl.GetMousePosition(), game_state.ui.panel_toolbox) {
		switch game_state.tool {
		case .View: break
		case .Select:
			update_figure_selection_tool()

			if rl.IsKeyPressed(.ESCAPE) {
				game_state.current_figure = nil
				clear(&game_state.selected_figures)
				game_state.state = .View
			}

			if rl.IsKeyPressed(.BACKSPACE) && check_bpm_text_action() == 1 || rl.IsKeyPressed(.DELETE) {
				if game_state.current_figure != nil do delete_current_figure()
				else if game_state.state == .Multiselection do delete_multiselected_figures()
			}

		case .Link:
			update_figure_link_tool()

			if rl.IsKeyPressed(.ESCAPE) {
				game_state.current_figure = nil
			}
		}
	}

	// ==== Render ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(BACKGROUND_COLOR)

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

	switch game_state.tool {
	case .View:
	case .Select:
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

		render_create_figure_ui()

	case .Link:
		if game_state.current_figure != nil {
			render_selected_figure(game_state.current_figure^, FIGURE_SELECTED_COLOR)
		}
	}

	render_toolbox_ui()
	render_error_msg()

	when ODIN_DEBUG {
		render_debug_info()
	}

	// Borrar memoria temporal
	free_all(context.temp_allocator)
}

// ==== OTHER CALLBACKS =======================================================

// In a web build, this is called when browser changes size. Remove
// the `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: c.int) {
	if game_state.window_size == (iv2 {w, h}) {
		return
	}

	game_state.window_size = {w, h}
	update_ui_dimensions()

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
