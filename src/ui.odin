package game

import rl "vendor:raylib"

import "core:c"
import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"

UI_FONT_SIZE   :: 12
UI_LINE_HEIGHT :: 30
UI_MARGIN      :: 15
UI_PADDING     :: 5
UI_BUTTON_SIZE :: UI_LINE_HEIGHT - UI_PADDING

// Tamaño del panel UI para dar a raylib
UI_PANEL_DIM :: rect {
	UI_MARGIN, UI_MARGIN,
	/* MAX ANCHO: text: */ 100 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40,
	/* ALTO: cabecera + 4 filas + padding final */ 5 * UI_LINE_HEIGHT + UI_PADDING,
}

// TODO: mover a game_state
bpm_text : [dynamic]u8
UI_figure_panel_dim := rect {
	0, UI_MARGIN,
	// 150 + 3*UI_LINE_HEIGHT + 3*UI_PADDING,
	/* MAX ANCHO: text: */ 100 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40,
	150,
}

// Se usa para determinar las propiedades de nuevas figuras
UI_Create_State :: struct {
	n_sides: uint,
	counter: int,
}

// Convertir el numero actual a cstring para mostrarlo en la UI
cstr_from_int :: proc(n: int, allocator := context.temp_allocator, loc := #caller_location) -> cstring {
	// Si es negativo, denota infinito
	if n < 0 {
		return "inf"
	}

	return fmt.caprintf("%d\x00", n, allocator, loc)
}

render_create_figure_ui :: proc() {
	// TODO: customizar estilos, se ve bastante como la caca
	using game_state.create_figure_ui

	rl.GuiPanel(UI_PANEL_DIM, "Create figure")

	// Posición inicial
	current_x : f32 = UI_PANEL_DIM.x + UI_PADDING
	current_y : f32 = UI_PANEL_DIM.y + /* saltar cabecera */ UI_LINE_HEIGHT

	// Número de lados de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(n_sides)))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			n_sides = min(n_sides + 1, FIGURE_MAX_SIDES)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			n_sides = max(n_sides - 1, 2)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	current_x = UI_PADDING + UI_MARGIN
	current_y += UI_LINE_HEIGHT

	// Contador de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Counter:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(counter))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
			counter = min(counter + 1, 100)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") && counter != -1 {
			counter = max(counter - 1, 0)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 40, UI_BUTTON_SIZE}, "inf") {
			counter = -1
		}
	}

	current_x = UI_PANEL_DIM.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// TODO: esto modifica otras cosas, no realmente la creación de nuevas
	// figuras. Mover a su propio panel?

	// Sincronizar puntos
	{
		rl.GuiLabel({current_x, current_y, 80, UI_LINE_HEIGHT}, "Sync beat(s)")
		current_x += 100 + UI_PADDING
		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
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
		rl.GuiLabel({current_x, current_y, 80, UI_LINE_HEIGHT}, "Reset counts")
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
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
}

render_figure_ui :: proc() {
	if game_state.state == .View {
		return
	}

	UI_figure_panel_dim.x = f32(game_state.window_size.x) - UI_figure_panel_dim.width - UI_MARGIN
	rl.GuiPanel(UI_figure_panel_dim, "Figure Options")

	current_x : f32 = UI_figure_panel_dim.x + UI_PADDING
	current_y : f32 = UI_figure_panel_dim.y + UI_LINE_HEIGHT

	using game_state.current_figure

	// Número de lados de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(n)))
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			n = min(n + 1, FIGURE_MAX_SIDES)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			n = max(n - 1, 2)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	current_x = UI_figure_panel_dim.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// Contador inicial de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Counter:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(point_counter_start))
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
			point_counter_start = min(point_counter_start + 1, 100)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") && point_counter_start != -1 {
			point_counter_start = max(point_counter_start - 1, 0)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 40, UI_BUTTON_SIZE}, "inf") {
			point_counter_start = -1
		}
	}

	current_x = UI_figure_panel_dim.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// Especificar las notas
	{
		rl.GuiLabel({current_x, current_y, 100, UI_LINE_HEIGHT}, "Sound Config:")
		current_x = UI_figure_panel_dim.x + UI_PADDING
		current_y += UI_LINE_HEIGHT

		n: uint = 0

		for note in 1..=game_state.current_figure.n {
			// TODO: usar caprintf("Vertex %d\x00", n+1)? Así queda el texto más junto
			rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Vertex")
			rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(n+1)))
			current_x += 100 + UI_PADDING

			if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "+") {
				note_value := int(game_state.current_figure.notes[n])
				if note_value < 9 {
					game_state.current_figure.notes[n] = Music_Notes(note_value+1)
				}
			}
			current_x += UI_LINE_HEIGHT + UI_PADDING

			rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, STRING_NOTES[game_state.current_figure.notes[n]])

			current_x += UI_LINE_HEIGHT

			if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_BUTTON_SIZE, UI_BUTTON_SIZE}, "-") {
				note_value := int(game_state.current_figure.notes[n])
				if note_value > 0 {
					game_state.current_figure.notes[n] = Music_Notes(note_value-1)
				}
			}
			current_x = UI_figure_panel_dim.x + UI_PADDING
			current_y += UI_LINE_HEIGHT
			n += 1
		}
	}
	
	// BPM config
	{
		char_count := 0
		mouse_on_text := false
		text_box := rect { current_x, current_y, 50, UI_LINE_HEIGHT }
		if len(bpm_text) == 0 || bpm_text[len(bpm_text)-1] != 0 {
			append(&bpm_text, 0)
		}

		if (rl.CheckCollisionPointRec(rl.GetMousePosition(), text_box)) {
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
				if (value >= '0') && (value <= '9') && (char_count < 2) {
					append(&bpm_text, 0)               // null terminator
					bpm_text[char_count] = u8(value)          // store character
					char_count += 1
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
			}
		}
		
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "BPM:")

		text_box = rect { current_x, current_y, 50, UI_LINE_HEIGHT }
		rl.DrawRectangleRec(text_box, rl.DARKGRAY)
		current_x += 120 + UI_PADDING

		rl.DrawText(cast(cstring) &bpm_text[0], i32(current_x), i32(current_y), 5, rl.WHITE)
	}

	current_x = UI_figure_panel_dim.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// Borrar figura
	// WARN: debe estar al final de la función: si se borra la figura y el
	// código siguiente usa game_state.current_figure, habrá un crash
	{
		rl.GuiLabel({current_x, current_y, 80, UI_LINE_HEIGHT}, "Delete")
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
			delete_current_figure()
		}
	}

	current_x = UI_figure_panel_dim.x + UI_PADDING
	current_y += UI_LINE_HEIGHT
	// TODO: no queda con el tamaño correcto, es un poco más grande
	UI_figure_panel_dim.height = current_y
}

render_debug_info :: proc() {
	current_x : c.int = UI_MARGIN
	current_y : c.int = game_state.window_size.y - 6 * (UI_FONT_SIZE + UI_PADDING/2) - UI_MARGIN

	rl.DrawText(
		fmt.caprintf("state: %w\x00", game_state.state, context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
	current_y += UI_FONT_SIZE + UI_PADDING/2

	rl.DrawText(
		fmt.caprintf("time: %1.5f\x00", rl.GetFrameTime(), context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
	current_y += UI_FONT_SIZE + UI_PADDING/2

	rl.DrawText(
		fmt.caprintf("simulation: %w\x00", game_state.simulation_running, context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
	current_y += UI_FONT_SIZE + UI_PADDING/2

	rl.DrawText(
		fmt.caprintf("zoom: %1.5f\x00", game_state.camera.zoom, context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
	current_y += UI_FONT_SIZE + UI_PADDING/2

	rl.DrawText(
		fmt.caprintf("n total figures: %d\x00", len(game_state.figures), context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
	current_y += UI_FONT_SIZE + UI_PADDING/2

	n_selected := 0
	if game_state.state == .Multiselection {
		n_selected = len(game_state.selected_figures)
	} else if game_state.current_figure != nil {
		n_selected = 1
	}

	rl.DrawText(
		fmt.caprintf("figures selected: %d\x00", n_selected, context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
}
