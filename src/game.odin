package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"
import "core:c"
import "core:math/rand"
import "core:strings"

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
	La_m1_, Si_m1, Do, Do_, Re, Re_, Mi, Fa, Fa_, Sol, Sol_, La, La_, Si, Do2, Do2_, Re2, Null,
}

Instrument :: enum u8 {
	Piano, Violin, Flauta, Tambor,
}

Percussion :: enum u8 {
	Floor_Tom, Tom, Bass, Snare, Crross_Stick, Plate_Bell, Charles_Open, Charles_Pedal, Ride_Cymbal, Crash_Cymbal, Hit_Hat, Null,
}

@(rodata)
STRING_NOTES := [Music_Notes]cstring {
	.La_m1_ = "La_m1#",
	.Si_m1 = "Si_m1",
	.Do = "Do",
	.Do_ = "Do#",
	.Re = "Re",
	.Re_ = "Re#",
	.Mi = "Mi",
	.Fa = "Fa",
	.Fa_ = "Fa#",
	.Sol = "Sol",
	.Sol_ = "Sol#",
	.La = "La",
	.La_ = "La#",
	.Si = "Si",
	.Do2 = "Do2",
	.Do2_ = "Do2#",
	.Re2 = "Re2",
	.Null = "---",
}


@(rodata)
STRING_NOTES_EN := [Music_Notes]cstring {
	.La_m1_ = "F_m1#",
	.Si_m1 = "G_m1",
	.Do = "A",
	.Do_ = "A#",
	.Re = "B",
	.Re_ = "B#",
	.Mi = "C",
	.Fa = "D",
	.Fa_ = "D#",
	.Sol = "E",
	.Sol_ = "E#",
	.La = "F",
	.La_ = "F#",
	.Si = "G",
	.Do2 = "A2",
	.Do2_ = "A2#",
	.Re2 = "B2",
	.Null = "---",
}


@(rodata)
INSTRUMENTS := [Instrument]cstring {
	.Piano = "Piano",
	.Violin = "Violin",
	.Flauta = "Flute",
	.Tambor = "Drum",
}

@(rodata)
INSTRUMENTS_TO_COLOR := [Instrument]rl.Color {
	.Piano = {0, 255, 0, 255},
	.Violin = {255, 0, 255, 255},
	.Flauta = {0, 128, 255, 255},
	.Tambor = {255, 128, 0, 255},
}

@(rodata)
PERCUSSIONS := [Percussion]cstring {
	//Debe tener el '_' en el string, si no, no encontrará el nombre del archivo
	.Floor_Tom = "Floor_Tom",
	.Tom = "Tom",
	.Bass = "Bass",
	.Snare = "Snare",
	.Crross_Stick = "Cross_Stick",
	.Plate_Bell = "Plate_Bell",
	.Charles_Open = "Charles_Open",
	.Charles_Pedal = "Charles_Pedal",
	.Ride_Cymbal = "Ride_Cymbal",
	.Crash_Cymbal = "Crash_Cymbal",
	.Hit_Hat = "Hit_Hat",
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
	SOUND_MATRIX: [Instrument][Music_Notes]rl.Sound,
	PERCUSSION_SOUNDS: [Percussion]rl.Sound,
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

	// BUG: no carga la fuente: no hay errores pero se sigue usando la fuente
	// por defecto. Tampoco con "assets/Ubuntu-Regular.ttf".
	ui.font = rl.LoadFontEx("assets/Roboto-Regular.ttf", 32, nil, 0)
	ensure(rl.IsFontValid(ui.font), "Invalid UI font")

	ui.creation_n_sides = 3
	ui.creation_counter = -1
	ui.volume = 0.5
	ui.bpm_text_box.box = rect { 0, 0, 50, UI_LINE_HEIGHT - 15 }
	ui.bpm_text_box.selected = false
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


	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
	rl.InitWindow(window_size.x, window_size.y, WINDOW_NAME)
	rl.InitAudioDevice()

	for i in Instrument {
		if i != .Tambor {
			c_inst := string(INSTRUMENTS[i])
			for n in Music_Notes {
				if n == .Null do continue
				c_note := string(STRING_NOTES[n])
				path   := [?]string { "assets/sounds/", c_inst, "_", c_note, ".wav" }
				concat := strings.concatenate(path[:], allocator = context.temp_allocator)
				cstr   := strings.clone_to_cstring(concat, allocator = context.temp_allocator)
				game_state.SOUND_MATRIX[i][n] = rl.LoadSound(cstr)
			}

		} else {
			for p in Percussion {
				if p == .Null do continue
				c_per := string(PERCUSSIONS[p])
				path := [?]string { "assets/sounds/Bateria_", c_per, ".wav" }
				concat := strings.concatenate(path[:], allocator = context.temp_allocator)
				cstr   := strings.clone_to_cstring(concat, allocator = context.temp_allocator)
				game_state.PERCUSSION_SOUNDS[p] = rl.LoadSound(cstr)
			}
		}
	}

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

	if !game_state.ui.bpm_text_box.selected {
		tool_changed := false
		if rl.IsKeyPressed(.ZERO) {
			game_state.tool = .View
			tool_changed = true
			set_msg("View Mode: Use ESC or mode keys to return")
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

	switch game_state.tool {
	case .View:
		if rl.IsKeyPressed(.ESCAPE) {
			game_state.tool = .Select
		}

	case .Select:
		if !rl.CheckCollisionPointRec(rl.GetMousePosition(), game_state.ui.panel_toolbox) {
			update_figure_selection_tool()

			if rl.IsKeyPressed(.ESCAPE) {
				game_state.current_figure = nil
				clear(&game_state.selected_figures)
				game_state.state = .View
			}

			if rl.IsKeyPressed(.BACKSPACE) && !game_state.ui.bpm_text_box.selected || rl.IsKeyPressed(.DELETE) {
				if game_state.current_figure != nil do delete_current_figure()
				else if game_state.state == .Multiselection do delete_multiselected_figures()
			}
		}

	case .Link:
		if !rl.CheckCollisionPointRec(rl.GetMousePosition(), game_state.ui.panel_toolbox) {
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
		render_regular_figure(f,INSTRUMENTS_TO_COLOR[f.instrument])
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
		render_toolbox_ui()

	case .Link:
		if game_state.current_figure != nil {
			render_selected_figure(game_state.current_figure^, FIGURE_SELECTED_COLOR)
		}
		render_toolbox_ui()
	}

	render_msg()

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
	rl.CloseAudioDevice()

	rl.UnloadFont(game_state.ui.font)
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
