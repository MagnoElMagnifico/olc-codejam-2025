package game

import rl "vendor:raylib"

import "core:fmt"
import "core:strconv"
import "core:strings"

UI_FONT_SIZE   :: 12
UI_LINE_HEIGHT :: 30
UI_MARGIN      :: 15
UI_PADDING     :: 5
UI_BUTTON_SIZE :: UI_LINE_HEIGHT - UI_PADDING

UI_ERROR_MSG_TIME  :: 5.0 // s
UI_ERROR_MSG_COLOR :: rl.RED

// Tamaño del panel UI para dar a raylib


// Se usa para determinar las propiedades de nuevas figuras
UI_State :: struct {
	font: rl.Font,

	// Panel de herramientas
	volume: f32,
	// La herramienta seleccionada actual está en game_state.tool

	// Panel de creación de nuevas figuras
	creation_n_sides: uint,
	creation_counter: int,

	// Dimensiones de los paneles que no sean constantes
	panel_toolbox: rect, // Este sí es constante creo
	panel_create_figure: rect,
	panel_figure: rect,

	// Mensajes al usuario
	error_message: cstring,
	error_needs_free: bool, // Innecesario por el momento
	error_timer: f32,
}


update_ui_dimensions :: proc() {
	PANEL_TOOLBOX_WIDTH :: 3 * UI_BUTTON_SIZE + 4 * UI_PADDING
	PANEL_FIGURE_WIDTH :: /* text: */ 100 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40

	game_state.ui.panel_toolbox = rect {
		x = f32(game_state.window_size.x) / 2 - PANEL_TOOLBOX_WIDTH / 2,
		y = UI_MARGIN,
		width = PANEL_TOOLBOX_WIDTH,
		height = UI_LINE_HEIGHT,
	}

	game_state.ui.panel_create_figure = rect {
		x = UI_MARGIN,
		y = UI_MARGIN,
		width = PANEL_FIGURE_WIDTH,
		height = /* header + 2 rows + padding */ 3 * UI_LINE_HEIGHT + UI_PADDING,
	}

	game_state.ui.panel_figure = rect {
		x = f32(game_state.window_size.x) - PANEL_FIGURE_WIDTH - UI_MARGIN,
		y = UI_MARGIN,
		width = PANEL_FIGURE_WIDTH,
		height = 150, // Esto depende de la figura seleccionada
	}
}

// TODO: mover todas las variables estáticas a game_state
bpm_text : [dynamic]u8
char_count := 1
textBox := rl.Rectangle({0, 0, 50, UI_LINE_HEIGHT - 15 })
mouse_on_text := false

render_toolbox_ui :: proc() {
	x := game_state.ui.panel_toolbox.x
	y := game_state.ui.panel_toolbox.y

	tool_changed := false

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "S") {
		game_state.tool = .Select
		tool_changed = true
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "L") {
		game_state.tool = .Link
		tool_changed = true
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "V") {
		game_state.tool = .View
		tool_changed = true
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	// Limpiar el estado para que no quede corrupto
	if tool_changed {
		game_state.current_figure = nil
		game_state.state = .View
		clear(&game_state.selected_figures)
	}

	/*
	// Sincronizar puntos
	{
		widget_label({current_x, current_y, 80, UI_LINE_HEIGHT}, "Sync beat(s)")
		current_x += 100 + UI_PADDING
		if widget_button({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
			if game_state.current_figure != nil {
				using game_state.current_figure
				point_seg_index = 0
				point_progress = 0

			} else if game_state.state == .Multiselection {
				for &f in game_state.selected_figures {
					f.point_seg_index = 0
					f.point_progress = 0
				}

			} else {
				// TODO: borrar esta operación porque podría fastidiar el
				// trabajo del usuario: desharía el sync creado manualmente
				for &f in game_state.figures {
					f.point_seg_index = 0
					f.point_progress = 0
				}
			}
		}
	}

	current_x = UI_PANEL_DIM.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// Reset contadores
	{
		widget_label({current_x, current_y, 80, UI_LINE_HEIGHT}, "Reset counts")
		current_x += 100 + UI_PADDING

		if widget_button({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
			if game_state.current_figure != nil {
				using game_state.current_figure
				point_counter = point_counter_start
			} else if game_state.state == .Multiselection {
				for &f in game_state.selected_figures {
					f.point_counter = f.point_counter_start
				}
			} else {
				for &f in game_state.figures {
					f.point_counter = f.point_counter_start
				}
			}
		}
	}

	current_x = UI_PANEL_DIM.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	//Volumen
	{
		widget_label({current_x, current_y, 50, UI_LINE_HEIGHT}, "Volume:")
		widget_label({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.volume)))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if widget_button({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			game_state.volume = min(game_state.volume + 1, 10)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			game_state.volume = max(game_state.volume - 1, 0)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	current_x = UI_PADDING + UI_MARGIN
	current_y += UI_LINE_HEIGHT
	*/
}

render_create_figure_ui :: proc() {
	using game_state.ui
	widget_panel(panel_create_figure, "Create figure")

	// Posición inicial
	x : f32 = panel_create_figure.x + UI_PADDING
	y : f32 = panel_create_figure.y + /* saltar cabecera */ UI_LINE_HEIGHT

	// Número de lados de la figura
	{
		widget_label({x,      y, 50, UI_LINE_HEIGHT}, "Sides:")
		widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(creation_n_sides)))
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			creation_n_sides = min(creation_n_sides + 1, FIGURE_MAX_SIDES)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			creation_n_sides = max(creation_n_sides - 1, 2)
		}
		x += UI_LINE_HEIGHT + UI_PADDING
	}

	x = UI_PADDING + UI_MARGIN
	y += UI_LINE_HEIGHT

	// Contador de la figura
	{
		widget_label({x,      y, 50, UI_LINE_HEIGHT}, "Counter:")
		widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(creation_counter))

		// añadir el width del elemento y padding para el siguiente
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
			creation_counter = min(creation_counter + 1, 100)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") && creation_counter != COUNTER_INF {
			creation_counter = max(creation_counter - 1, 0)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, 40, UI_BUTTON_SIZE}, "inf") {
			creation_counter = COUNTER_INF
		}
	}

	x = panel_create_figure.x + UI_PADDING
	y += UI_LINE_HEIGHT

}

render_figure_ui :: proc() {
	if game_state.state == .View {
		return
	}

	widget_panel(game_state.ui.panel_figure, "Figure Options")

	x := game_state.ui.panel_figure.x + UI_PADDING
	y := game_state.ui.panel_figure.y + UI_LINE_HEIGHT

	// Número de lados de la figura
	{
		widget_label({x,      y, 50, UI_LINE_HEIGHT}, "Sides:")
		widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.current_figure.n)))
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			game_state.current_figure.n = min(game_state.current_figure.n + 1, FIGURE_MAX_SIDES)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			game_state.current_figure.n = max(game_state.current_figure.n - 1, 2)
		}
		x += UI_LINE_HEIGHT + UI_PADDING
	}

	x = game_state.ui.panel_figure.x + UI_PADDING
	y += UI_LINE_HEIGHT

	// Contador inicial de la figura
	{
		widget_label({x, y, 50, UI_LINE_HEIGHT}, "Counter:")
		widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(game_state.current_figure.point_counter_start))
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
			game_state.current_figure.point_counter_start = min(game_state.current_figure.point_counter_start + 1, 100)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") &&
				game_state.current_figure.point_counter_start != COUNTER_INF {
			game_state.current_figure.point_counter_start = max(game_state.current_figure.point_counter_start - 1, 0)
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, 40, UI_BUTTON_SIZE}, "inf") {
			game_state.current_figure.point_counter_start = COUNTER_INF
		}
	}

	x = game_state.ui.panel_figure.x + UI_PADDING
	y += UI_LINE_HEIGHT

	// Especificar las notas
	{
		widget_label({x, y, 100, UI_LINE_HEIGHT}, "Sound Config:")
		y += UI_LINE_HEIGHT

		for vertex_index in 0..<game_state.current_figure.n {
			widget_label(
				{x, y, 50, UI_LINE_HEIGHT},
				fmt.caprintf("Vertex %d", vertex_index + 1, allocator = context.temp_allocator),
			)
			x += 100 + UI_PADDING

			if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
				note_value := int(game_state.current_figure.notes[vertex_index])
				if note_value < 9 {
					game_state.current_figure.notes[vertex_index] = Music_Notes(note_value+1)
				}
			}
			x += UI_LINE_HEIGHT + UI_PADDING

			widget_label({x, y, 50, UI_LINE_HEIGHT}, STRING_NOTES[game_state.current_figure.notes[vertex_index]])

			x += UI_LINE_HEIGHT

			if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") {
				note_value := int(game_state.current_figure.notes[vertex_index])
				if note_value > 0 {
					game_state.current_figure.notes[vertex_index] = Music_Notes(note_value-1)
				}
			}

			x = game_state.ui.panel_figure.x + UI_PADDING
			y += UI_LINE_HEIGHT
		}
	}
	
	// BPM config
	{
		if len(bpm_text) == 0 || bpm_text[len(bpm_text)-1] != 0 {
			append(&bpm_text,48)
			append(&bpm_text,0)
			char_count = 1
		}

		buf: [32]u8
		str := strconv.itoa(buf[:], int(f32(game_state.current_figure.frecuency * 60)))
		if !mouse_on_text && int(f32(game_state.current_figure.frecuency * 60)) != strconv.atoi(strings.string_from_ptr(&bpm_text[0], len(bpm_text))){
			for len(bpm_text) > 1{
				char_count -= 1
				if char_count < 0 {
					char_count = 0
				}else{
					pop(&bpm_text) // quitar char
					bpm_text[char_count] = 0 // null terminator
				}
			}
			for c in str{
				append(&bpm_text, 0)               // null terminator
				bpm_text[char_count] = u8(c)          // añadir char
				char_count += 1
			}

		}

		{
			if len(bpm_text) == 0 || bpm_text[len(bpm_text)-1] != 0 {
				append(&bpm_text, 0)
			}

			if (rl.CheckCollisionPointRec(rl.GetMousePosition(), textBox)) {
				rl.SetMouseCursor(rl.MouseCursor.IBEAM)
				if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
					mouse_on_text = true
				}
			} else {
				rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
				if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
					mouse_on_text = false
					if strconv.atoi(strings.string_from_ptr(&bpm_text[0], len(bpm_text))) < 1 {
						char_count -= 1
						if char_count < 0 {
							char_count = 0
						} else {
							pop(&bpm_text) // quitar valor < 1
						}
						append(&bpm_text, 0) // null terminator
						bpm_text[char_count] = 49 //añadir el 1
						char_count += 1
					}
				}
			}
			if mouse_on_text {
				value := rl.GetCharPressed()
				for value > 0 {
					if (value >= '0') && (value <= '9') && (char_count < 3) {
						append(&bpm_text, 0)               // null terminator

						bpm_text[char_count] = u8(value)          // store character
						char_count += 1
						input_bmp, _ := strconv.parse_uint(string((cast(cstring) &bpm_text[0])))
						game_state.current_figure.frecuency = f32(input_bmp) / f32(60.0)
						update_figure_radius(game_state.current_figure)
					}
					value = rl.GetCharPressed()
				}

				if rl.IsKeyPressed(.BACKSPACE) {
					char_count -= 1
					if char_count < 0 {
						char_count = 0
					} else {
						pop(&bpm_text) // remove character
						bpm_text[char_count] = 0 // null terminator
					}
					input_bmp, _ := strconv.parse_uint(string((cast(cstring) &bpm_text[0])))
					game_state.current_figure.frecuency = f32(input_bmp) / f32(60.0)
					update_figure_radius(game_state.current_figure)
				}
			}

			widget_label({x, y, 50, UI_LINE_HEIGHT}, "Bpm:")
			x += 100 + UI_PADDING

			rl.DrawRectangleRec(textBox, rl.DARKGRAY)
			textBox = rl.Rectangle({x, y+8, 50, UI_LINE_HEIGHT - 15 })
			x += UI_PADDING

			rl.DrawText(cast(cstring) &bpm_text[0], i32(x), i32(y)+10, 5, rl.WHITE)

			// BUG: esto no se puede ejecutar cada frame, sino solo cuando se
			// confirme el valor. De lo contrario, update_figure_radius() querrá
			// cambiar el radio de la figura mientras el usuario quiere usar el
			// ratón. Este if es solo un apaño.
		}
	}

	x = game_state.ui.panel_figure.x + UI_PADDING
	y += UI_LINE_HEIGHT

	// Borrar figura
	// WARN: debe estar al final de la función: si se borra la figura y el
	// código siguiente usa game_state.current_figure, habrá un crash
	{
		widget_label({x, y, 80, UI_LINE_HEIGHT}, "Delete")
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
			delete_current_figure()
		}
	}

	x = game_state.ui.panel_figure.x + UI_PADDING
	y += UI_LINE_HEIGHT + UI_PADDING

	game_state.ui.panel_figure.height = y - game_state.ui.panel_figure.y
}

set_error_msg :: proc(s: cstring) {
	game_state.ui.error_message = s
	game_state.ui.error_timer = UI_ERROR_MSG_TIME
}

render_error_msg :: proc() {
	if game_state.ui.error_timer <= 0 do return

	game_state.ui.error_timer -= rl.GetFrameTime()
	width := rl.MeasureText(game_state.ui.error_message, UI_FONT_SIZE)
	pos_x := game_state.window_size.x - UI_MARGIN - width
	pos_y := game_state.window_size.y - UI_MARGIN - UI_FONT_SIZE
	rl.DrawText(game_state.ui.error_message, pos_x, pos_y, UI_FONT_SIZE, UI_ERROR_MSG_COLOR)
}

when ODIN_DEBUG {
	render_debug_info :: proc() {
		x : i32 = UI_MARGIN
		y : i32 = game_state.window_size.y - 7 * (UI_FONT_SIZE + UI_PADDING/2) - UI_MARGIN

		rl.DrawText(
			fmt.caprintf("tool: %w", game_state.tool, allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		rl.DrawText(
			fmt.caprintf("selection: %w", game_state.state, allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		rl.DrawText(
			fmt.caprintf("frame time: %1.5f", rl.GetFrameTime(), allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		rl.DrawText(
			fmt.caprintf("simulation: %w", game_state.simulation_running, allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		rl.DrawText(
			fmt.caprintf("zoom: %1.5f", game_state.camera.zoom, allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		rl.DrawText(
			fmt.caprintf("figures len: %d, figures cap: %d", len(game_state.figures), cap(game_state.figures), allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
		y += UI_FONT_SIZE + UI_PADDING/2

		n_selected := 0
		if game_state.state == .Multiselection {
			n_selected = len(game_state.selected_figures)
		} else if game_state.current_figure != nil {
			n_selected = 1
		}

		rl.DrawText(
			fmt.caprintf("figures selected: %d", n_selected, allocator = context.temp_allocator),
			x, y,
			UI_FONT_SIZE,
			rl.WHITE,
		)
	}
}

check_bpm_text_action :: proc() -> int{
	if mouse_on_text {
		return 0
	}else{
		return 1
	}
}

// Convertir el numero actual a cstring para mostrarlo en la UI
cstr_from_int :: proc(n: int, allocator := context.temp_allocator) -> cstring {
	// Si es negativo, denota infinito
	if n < 0 {
		return "inf"
	}

	return fmt.caprintf("%d", n, allocator = allocator)
}

