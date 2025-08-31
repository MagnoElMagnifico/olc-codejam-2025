package game

import rl "vendor:raylib"

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:log"

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
	creation_instrument: Instrument,

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
		/* sincronizar y reset */ 100 + 2*120 + 2*UI_PADDING +
		/* volumen */             100 + 50 + UI_PADDING + 150 +
		/* extra */               10

    PANEL_GENERAL_WIDTH :: /* text: */ 150 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40

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
		height = /* header + 2 rows + padding */ 4 * UI_LINE_HEIGHT + 2*UI_PADDING,
	}

	game_state.ui.panel_figure = rect {
		x = f32(game_state.window_size.x) - PANEL_GENERAL_WIDTH - UI_MARGIN,
		y = UI_MARGIN,
		width = PANEL_GENERAL_WIDTH,
		height = 150, // Esto depende de la figura seleccionada
	}
}

render_toolbox_ui :: proc() {
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
		set_msg("View Mode: Use ESC or mode keys to return")
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

	// espacio entre las herramientas y estos botones
	x += 100

	// Sincronizar puntos
	{
		if widget_button({x, y+UI_PADDING/2, 120, UI_BUTTON_SIZE}, "Reset cycle") {
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
	x += 120 + UI_PADDING

	// Reset contadores
	{
		if widget_button({x, y+UI_PADDING/2, 120, UI_BUTTON_SIZE}, "Reset counts") {
			if game_state.current_figure != nil {
				using game_state.current_figure
				point_counter = point_counter_start

			}else if game_state.state == .Multiselection {
				if len(game_state.selected_figures) == 1{
					game_state.selected_figures[0].point_counter = game_state.selected_figures[0].point_counter_start
					game_state.selected_figures[0].is_active = true
				}else{
					for &f in game_state.selected_figures {
					f.point_counter = f.point_counter_start
						if f.previous_figure == nil {
							f.is_active = true
						}
					}
				}
			} else {
				for &f in game_state.figures {
					f.point_counter = f.point_counter_start
					if f.previous_figure == nil {
						f.is_active = true
					}
				}
			}
		}
	}
	x += 120 + UI_PADDING

	// espacio entre estos botones y el volumen
	x += 100

	// Volumen
	{
		// TODO: escala logarítmica
		widget_label({x, y, 50, UI_LINE_HEIGHT}, "Volume")
		x += 50 + UI_PADDING

		game_state.ui.volume = widget_slider(
			size = {x, y, 150, UI_LINE_HEIGHT},
			current = game_state.ui.volume,
		)
	}
}

render_create_figure_ui :: proc() {
	using game_state.ui
	widget_panel(panel_create_figure, "Create figure")

	LABEL_PROPORTION  :: 0.6
	INF_BUTTON_FACTOR :: 1.5
	INF_BUTTON_WIDTH  :: (UI_LINE_HEIGHT - UI_PADDING/2) * INF_BUTTON_FACTOR + UI_PADDING

	// Posición inicial
	x := panel_create_figure.x + UI_PADDING + PANEL_BORDER_SIZE
	y := panel_create_figure.y + /* saltar cabecera */ UI_LINE_HEIGHT

	// Número de lados de la figura
	widget_number(
		text = "Sides",
		number = &creation_n_sides,
		minimum = 2,
		maximum = FIGURE_MAX_SIDES,
		size = {x, y, panel_create_figure.width - PANEL_BORDER_SIZE - INF_BUTTON_WIDTH, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
	)

	y += UI_LINE_HEIGHT

	// Contador de la figura
	widget_number_inf(
		text = "Counter",
		number = &creation_counter,
		minimum = 1,
		maximum = 100,
		size = {x, y, panel_create_figure.width-PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
	)

	y += UI_LINE_HEIGHT

	// Instrumento
	widget_enum(
		text = "Instrument",
		value = &creation_instrument,
		enum_str = INSTRUMENTS,
		size = {x, y, panel_create_figure.width - PANEL_BORDER_SIZE - INF_BUTTON_WIDTH, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
	)
}

render_figure_ui :: proc() {
	widget_panel(game_state.ui.panel_figure, "Figure Options")

	LABEL_PROPORTION  :: 0.6
	INF_BUTTON_FACTOR :: 1.5
	INF_BUTTON_WIDTH  :: (UI_LINE_HEIGHT - UI_PADDING/2) * INF_BUTTON_FACTOR + UI_PADDING

	x := game_state.ui.panel_figure.x + UI_PADDING + PANEL_BORDER_SIZE
	y := game_state.ui.panel_figure.y + /* saltar cabecera */ UI_LINE_HEIGHT

	// Número de lados de la figura
	widget_number(
		text = "Sides",
		number = &game_state.current_figure.n,
		minimum = 2,
		maximum = FIGURE_MAX_SIDES,
		size = {x, y, game_state.ui.panel_figure.width - PANEL_BORDER_SIZE - INF_BUTTON_WIDTH, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
	)

	y += UI_LINE_HEIGHT

	// Contador inicial de la figura
	widget_number_inf(
		text = "Counter",
		number = &game_state.current_figure.point_counter_start,
		minimum = 1,
		maximum = 100,
		size = {x, y, game_state.ui.panel_figure.width - PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
		inf_size = 1.5,
	)

	y += UI_LINE_HEIGHT

	// Instrumento
	widget_enum(
		text = "Instrument",
		value = &game_state.current_figure.instrument,
		enum_str = INSTRUMENTS,
		size = {x, y, game_state.ui.panel_figure.width - PANEL_BORDER_SIZE - INF_BUTTON_WIDTH, UI_LINE_HEIGHT},
		label = LABEL_PROPORTION,
	)

	y += UI_LINE_HEIGHT

	// Especificar las notas
	{
		widget_label(
			position = {x, y, game_state.ui.panel_figure.width - PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
			text = "--- Music Notes ---",
			hcenter = true,
		)
		y += UI_LINE_HEIGHT

		for vertex_index in 0..<game_state.current_figure.n {
			if game_state.current_figure.instrument != .Tambor {
				widget_enum(
					text = fmt.caprintf("Vertex %d", vertex_index + 1, allocator = context.temp_allocator),
					value = &game_state.current_figure.notes[vertex_index],
					enum_str = STRING_NOTES,
					size = {x, y, game_state.ui.panel_figure.width-PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
					label = 0.4,
				)
			} else {
				widget_enum(
					text = fmt.caprintf("Vertex %d", vertex_index + 1, allocator = context.temp_allocator),
					value = &game_state.current_figure.percussions[vertex_index],
					enum_str = PERCUSSIONS,
					size = {x, y, game_state.ui.panel_figure.width-PANEL_BORDER_SIZE, UI_LINE_HEIGHT},
					label = 0.4,
				)
			}
			y += UI_LINE_HEIGHT
		}
	}

	// No hay necesidad de un aumento de y aquí, ya que se añadió en el for
	// superior

	// BPM config
	when false {
		bpm := game_state.current_figure.frecuency * 60
		if widget_slider_number(
			size = {x, y, game_state.ui.panel_create_figure.width - PANEL_BORDER_SIZE - 3*UI_PADDING, UI_LINE_HEIGHT},
			current = &bpm,
			minimum = FIGURE_MIN_FRECUENCY * 60,
			maximum = FIGURE_MAX_FRECUENCY * 60,
			fmt_str = "  %3.1f BPM",
		) {
			game_state.current_figure.frecuency = bpm / 60
			update_figure_radius(game_state.current_figure)
		}
	} else {
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
					if game_state.ui.bpm_text_box.value > 660 {
						game_state.ui.bpm_text_box.value = 660
					}
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

		widget_label({x, y, 50, UI_LINE_HEIGHT}, "BPM")
		x += 100 + UI_PADDING
		game_state.ui.bpm_text_box.box = rl.Rectangle({x, y+7, 50, UI_LINE_HEIGHT - 15 })
		rl.DrawRectangleRec(game_state.ui.bpm_text_box.box, rl.DARKGRAY)
		x += UI_PADDING

		rl.DrawText(
			fmt.caprintf("%d", game_state.ui.bpm_text_box.value, allocator = context.temp_allocator),
			i32(x), i32(y+9),
			UI_FONT_SIZE,
			rl.WHITE,
		)
	}

	x = game_state.ui.panel_figure.x + UI_PADDING + PANEL_BORDER_SIZE
	y += UI_LINE_HEIGHT

	// Borrar figura
	// WARN: debe estar al final de la función: si se borra la figura y el
	// código siguiente usa game_state.current_figure, habrá un crash
	if widget_button({x + game_state.ui.panel_figure.width / 2 - 75 / 2, y+UI_PADDING/2, 75, UI_BUTTON_SIZE}, "Delete") {
		delete_current_figure()
	}

	y += UI_LINE_HEIGHT + UI_PADDING
	game_state.ui.panel_figure.height = y - game_state.ui.panel_figure.y
}

set_msg :: proc(s: cstring, err := false) {
	game_state.ui.message = s
	game_state.ui.message_is_error = err
	game_state.ui.message_timer = UI_MSG_TIME
}

render_msg :: proc() {
	if game_state.ui.message_timer <= 0 do return

	// TODO: Fade?
	game_state.ui.message_timer -= rl.GetFrameTime()
	widget_label(
		position = { 0, UI_MARGIN, f32(game_state.window_size.x), UI_LINE_HEIGHT },
		text = game_state.ui.message,
		color = UI_MSG_ERROR_COLOR if game_state.ui.message_is_error else UI_MSG_COLOR,
		hcenter = true,
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

// Convertir el numero actual a cstring para mostrarlo en la UI
cstr_from_int :: proc(n: int, allocator := context.temp_allocator) -> cstring {
	// Si es negativo, denota infinito
	if n < 0 {
		return "inf"
	}

	return fmt.caprintf("%d", n, allocator = allocator)
}

