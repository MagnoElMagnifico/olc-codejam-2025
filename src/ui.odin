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

UI_MSG_WIDTH       :: 200 // px
UI_MSG_TIME        :: 5.0 // s
UI_MSG_COLOR       :: rl.WHITE
UI_MSG_ERROR_COLOR :: rl.RED

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
	bpm_text_box: Uint_Text_Box,

	// Mensajes al usuario
	message: cstring,
	message_is_error: bool,
	message_timer: f32,
}


update_ui_dimensions :: proc() {
	PANEL_TOOLBOX_WIDTH ::
		/* herramientas */        4 * UI_BUTTON_SIZE + 3 * UI_PADDING +
		/* sincronizar y reset */ 100 + 2*150 + 2*UI_PADDING +
		/* volumen */             100 + 50 + UI_PADDING + 100

    PANEL_FIGURE_WIDTH :: /* text: */ 250 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40
    PANEL_GENERAL_WIDTH :: /* text: */ 100 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40

	game_state.ui.panel_toolbox = rect {
		x = f32(game_state.window_size.x) / 2 - PANEL_TOOLBOX_WIDTH / 2,
		y = f32(game_state.window_size.y) - UI_LINE_HEIGHT - UI_MARGIN,
		width = PANEL_TOOLBOX_WIDTH,
		height = UI_LINE_HEIGHT,
	}

	game_state.ui.panel_create_figure = rect {
		x = UI_MARGIN,
		y = UI_MARGIN,
		width = PANEL_GENERAL_WIDTH,
		height = /* header + 2 rows + padding */ 3 * UI_LINE_HEIGHT + 2*UI_PADDING,
	}

	game_state.ui.panel_figure = rect {
		x = f32(game_state.window_size.x) - PANEL_FIGURE_WIDTH - UI_MARGIN,
		y = UI_MARGIN,
		width = PANEL_FIGURE_WIDTH,
		height = 150, // Esto depende de la figura seleccionada
	}
}

render_toolbox_ui :: proc() {
	// TODO: dibujar fondo y hacerlo más bonito
	x := game_state.ui.panel_toolbox.x
	y := game_state.ui.panel_toolbox.y

	tool_changed := false

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "S", highlight = game_state.tool == .Select) {
		game_state.tool = .Select
		tool_changed = true
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "L", highlight = game_state.tool == .Link) {
		game_state.tool = .Link
		tool_changed = true
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	if widget_button({x, y, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "V", highlight = game_state.tool == .View) {
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
	x += UI_BUTTON_SIZE + UI_PADDING

	// espacio entre las herramientas y estos botones
	x += 100

	// Sincronizar puntos
	{
		if widget_button({x, y+UI_PADDING/2, 150, UI_BUTTON_SIZE}, "Sync beats") {
			if game_state.current_figure != nil {
				using game_state.current_figure
				point_seg_index = 0
				point_progress = 0

			} else if game_state.state == .Multiselection {
				for &f in game_state.selected_figures {
					f.point_seg_index = 0
					f.point_progress = 0
				}
			}
		}
	}
	x += 150 + UI_PADDING

	// Reset contadores
	{
		if widget_button({x, y+UI_PADDING/2, 150, UI_BUTTON_SIZE}, "Reset counts") {
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
	x += 150 + UI_PADDING

	// espacio entre estos botones y el volumen
	x += 100

	// Volumen
	{
		// TODO: escala logarítmica
		widget_label({x, y, 50, UI_LINE_HEIGHT}, "Volume:")
		x += 50 + UI_PADDING

		// TODO: usar volume solo en el rango [0, 1]
		game_state.ui.volume = 10 * widget_slider(
			size = {x, y, 100, UI_LINE_HEIGHT},
			current = game_state.ui.volume / 10,
		)

		when false {
			widget_label({x, y, 50, UI_LINE_HEIGHT}, "Volume:")
			widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.ui.volume)))

			// añadir el width del elemento y padding para el siguiente
			x += 100 + UI_PADDING

			if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
				game_state.ui.volume = min(game_state.ui.volume + 1, 10)
			}
			x += UI_LINE_HEIGHT + UI_PADDING

			if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
				game_state.ui.volume = max(game_state.ui.volume - 1, 0)
			}
			x += UI_LINE_HEIGHT + UI_PADDING
		}
	}
}

render_create_figure_ui :: proc() {
	using game_state.ui
	widget_panel(panel_create_figure, "Create figure")

	// Posición inicial
	x : f32 = panel_create_figure.x + UI_PADDING + PANEL_BORDER_SIZE
	y : f32 = panel_create_figure.y + /* saltar cabecera */ UI_LINE_HEIGHT

	// Número de lados de la figura
	// TODO: convertir otros elementos de la UI a esto
	widget_number(
		text = "Sides:",
		number = &creation_n_sides,
		minimum = 2,
		maximum = FIGURE_MAX_SIDES,
		size = {x, y, panel_create_figure.width-PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
		label = 0.7,
	)

	x = UI_PADDING + UI_MARGIN + PANEL_BORDER_SIZE
	y += UI_LINE_HEIGHT

	// Contador de la figura
	widget_number_inf(
		text = "Counter:",
		number = &creation_counter,
		minimum = 1,
		maximum = 100,
		size = {x, y, panel_create_figure.width-PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
		label = 0.7,
	)

	when false {
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
	when false {
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
}

render_figure_ui :: proc() {
	if game_state.state == .View {
		return
	}

	widget_panel(game_state.ui.panel_figure, "Figure Options")

	x := game_state.ui.panel_figure.x + 6*UI_PADDING
	y := game_state.ui.panel_figure.y + UI_LINE_HEIGHT

	// Número de lados de la figura
	{
		widget_label({x,      y, 50, UI_LINE_HEIGHT}, "Sides:")
		widget_label({x + 50, y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.current_figure.n)))
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			game_state.current_figure.n = min(game_state.current_figure.n + 1, FIGURE_MAX_SIDES)
		}
		x += UI_LINE_HEIGHT + 6*UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			game_state.current_figure.n = max(game_state.current_figure.n - 1, 2)
		}
		x += UI_LINE_HEIGHT + 6*UI_PADDING
	}

	x = game_state.ui.panel_figure.x + 6*UI_PADDING
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

	x = game_state.ui.panel_figure.x + 6*UI_PADDING
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

			if(INSTRUMENTS[game_state.current_figure.instrument] != "Drum"){
				if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
					note_value := int(game_state.current_figure.notes[vertex_index])
					if note_value < len(STRING_NOTES) - 1 {
						game_state.current_figure.notes[vertex_index] = Music_Notes(note_value+1)
					}
				}
				x += UI_LINE_HEIGHT + 6*UI_PADDING

			widget_label({x, y, 50, UI_LINE_HEIGHT}, STRING_NOTES[game_state.current_figure.notes[vertex_index]])

				x += UI_LINE_HEIGHT + 6*UI_PADDING

				if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") {
					note_value := int(game_state.current_figure.notes[vertex_index])
					if note_value > 0 {
						game_state.current_figure.notes[vertex_index] = Music_Notes(note_value-1)
					}
				}
			}else{
				if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
					p_value := int(game_state.current_figure.percussions[vertex_index])
					if p_value < len(PERCUSSIONS) - 1 {
						game_state.current_figure.percussions[vertex_index] = Percussion(p_value+1)
					}
				}
				x += UI_LINE_HEIGHT

				widget_label({x, y, 120, UI_LINE_HEIGHT}, PERCUSSIONS[game_state.current_figure.percussions[vertex_index]])

				x += UI_LINE_HEIGHT + 12*UI_PADDING

				if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") {
					p_value := int(game_state.current_figure.percussions[vertex_index])
					if p_value > 0 {
						game_state.current_figure.percussions[vertex_index] = Percussion(p_value-1)
					}
				}
			}
			x = game_state.ui.panel_figure.x + 6*UI_PADDING
			y += UI_LINE_HEIGHT
		}
	}
	
	x = game_state.ui.panel_figure.x + 6*UI_PADDING
	//No hay necesidad de un aumento de y aquí, ya que se añadió en el for superior

	//Instrumento
	{
		widget_label({x, y, 60, UI_LINE_HEIGHT}, "Instrument: ")
		x += 100 + UI_PADDING

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
			instrument := int(game_state.current_figure.instrument)
			if instrument < len(INSTRUMENTS) - 1 {
				game_state.current_figure.instrument = Instrument(instrument+1)
			}
		}
		x += UI_LINE_HEIGHT + UI_PADDING

		widget_label({x, y, 65, UI_LINE_HEIGHT}, INSTRUMENTS[game_state.current_figure.instrument])

		x += UI_LINE_HEIGHT+15

		if widget_button({x, y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") {
			instrument := int(game_state.current_figure.instrument)
			if instrument > 0 {
				game_state.current_figure.instrument = Instrument(instrument-1)
			}
		}
		x = game_state.ui.panel_figure.x + UI_PADDING
		y += UI_LINE_HEIGHT
	}
	
	// BPM config
	{
		if !game_state.ui.bpm_text_box.selected && uint(f32(game_state.current_figure.frecuency * 60)) != game_state.ui.bpm_text_box.value {
			game_state.ui.bpm_text_box.value = uint(f32(game_state.current_figure.frecuency * 60))
		}

		if (rl.CheckCollisionPointRec(rl.GetMousePosition(), game_state.ui.bpm_text_box.box)) {
			rl.SetMouseCursor(rl.MouseCursor.IBEAM)
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				game_state.ui.bpm_text_box.selected = true
			}
		} else {
			rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				game_state.ui.bpm_text_box.selected = false
				if game_state.ui.bpm_text_box.value < 1 {
					game_state.ui.bpm_text_box.value = 60
				}
			}
		}
		if game_state.ui.bpm_text_box.selected {
			value := rl.GetCharPressed()
			for value > 0 {
				if (value >= '0') && (value <= '9') && game_state.ui.bpm_text_box.value <= 99 {
					game_state.ui.bpm_text_box.value = game_state.ui.bpm_text_box.value*10+(uint(value)-'0')
				}
				value = rl.GetCharPressed()
			}

			if rl.IsKeyPressed(.BACKSPACE) {
				if game_state.ui.bpm_text_box.value <= 9 {
					game_state.ui.bpm_text_box.value = 0
				} else {
					game_state.ui.bpm_text_box.value /= 10
				}
			}
		}

		game_state.current_figure.frecuency = f32(game_state.ui.bpm_text_box.value) / 60
		update_figure_radius(game_state.current_figure)

		widget_label({x, y, 50, UI_LINE_HEIGHT}, "Bpm:")
		x += 100 + UI_PADDING
		game_state.ui.bpm_text_box.box = rl.Rectangle({x, y-2, 50, UI_LINE_HEIGHT - 15 })
		rl.DrawRectangleRec(game_state.ui.bpm_text_box.box, rl.DARKGRAY)
		x += UI_PADDING

		rl.DrawText(
		fmt.caprintf("%d", game_state.ui.bpm_text_box.value, allocator = context.temp_allocator),
		i32(x), i32(y),
		UI_FONT_SIZE,
		rl.WHITE,
		)

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

set_msg :: proc(s: cstring, err := false) {
	game_state.ui.message = s
	game_state.ui.message_is_error = err
	game_state.ui.message_timer = UI_MSG_TIME
}

render_error_msg :: proc() {
	if game_state.ui.message_timer <= 0 do return

	game_state.ui.message_timer -= rl.GetFrameTime()
	pos_x := f32(game_state.window_size.x) - UI_MARGIN - UI_MSG_WIDTH
	pos_y := f32(game_state.window_size.y) - UI_MARGIN - UI_FONT_SIZE
	widget_label(
		position = { pos_x, pos_y, UI_MSG_WIDTH, UI_LINE_HEIGHT },
		text = game_state.ui.message,
		color = UI_MSG_ERROR_COLOR if game_state.ui.message_is_error else UI_MSG_COLOR,
	)
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
	if game_state.ui.bpm_text_box.selected {
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

