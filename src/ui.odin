package game

import rl "vendor:raylib"
import "core:fmt"
import "core:c"

UI_PADDING     :: 5
UI_LINE_HEIGHT :: 30
UI_MARGIN      :: 15
UI_Y_POS       :: UI_MARGIN + UI_LINE_HEIGHT
UI_FONT_SIZE   :: 12

// Tamaño del panel UI para dar a raylib
UI_REAL_PANEL_DIM :: rect {
	UI_MARGIN, UI_MARGIN,
	/* MAX ANCHO: text: */ 100 + /* 3 botones: */ 2*UI_LINE_HEIGHT + 5*UI_PADDING + 40,
	/* ALTO: 3 filas */ 3 * UI_LINE_HEIGHT + (3 + 1) * UI_PADDING,
}

// Tamaño del panel UI como bounding box
UI_PANEL_DIM :: rect {
	UI_MARGIN, UI_MARGIN,
	100 + 2*UI_LINE_HEIGHT + 5*UI_PADDING + 40,
	/* ALTO: Uno más por la cabecera */ 4*UI_LINE_HEIGHT + (4+1) * UI_PADDING,
}

// Igual que antes pero para el panel de la figura
/*UI_FIGURE_PANEL_DIM :: rect {
	UI_MARGIN,
	UI_MARGIN,
	/* text: */ 100 + /* 3 botones: */ 3*UI_LINE_HEIGHT + 3*UI_PADDING,
	3 * UI_LINE_HEIGHT + UI_PADDING,
}

UI_FIGURE_REAL_PANEL_DIM :: rect {
	UI_MARGIN,
	UI_MARGIN,
	100 + 3*UI_LINE_HEIGHT + 3*UI_PADDING,
	4*UI_LINE_HEIGHT+UI_PADDING,
}*/

UI_State :: struct {
	// Se usa para determinar el número de lados de nuevas figuras
	n_sides: uint,
	counter: int,
}

UI_Figure_State :: struct{
	n_sides: uint,
	n_notes: [dynamic]uint,
}

// Convertir el numero actual a cstring para mostrarlo en la UI
cstr_from_int :: proc(n: int, allocator := context.temp_allocator, loc := #caller_location) -> cstring {
	// Si es negativo, denota infinito
	if n < 0 {
		return "inf"
	}

	return fmt.caprintf("%d\x00", n, allocator, loc)
}

render_ui :: proc() {
	// TODO: customizar estilos, se ve bastante como la caca
	using game_state.ui

	current_x : f32 = UI_PADDING + UI_MARGIN // posicion inicial
	current_y : f32 = UI_Y_POS

	rl.GuiPanel(UI_REAL_PANEL_DIM, "Create figure")

	// Número de lados de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.ui.n_sides)))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			n_sides = min(n_sides + 1, 25)

			if game_state.state == .Selected_Figure {
				game_state.current_figure.n = n_sides
			}
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			// TODO: permitir líneas? Habría un salto de 2 a 1 (no hay figuras de 2 lados
			n_sides = max(n_sides - 1, 3)

			if game_state.state == .Selected_Figure {
				game_state.current_figure.n = n_sides
			}
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	current_x = UI_PADDING + UI_MARGIN
	current_y += UI_LINE_HEIGHT

	// Contador de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Counter:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(game_state.ui.counter))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			counter = min(counter + 1, 100)

			if game_state.state == .Selected_Figure {
				game_state.current_figure.point_counter = counter
			}
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") && counter != -1 {
			counter = max(counter - 1, 0)

			if game_state.state == .Selected_Figure {
				game_state.current_figure.point_counter = counter
			}
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 40, UI_LINE_HEIGHT-UI_PADDING}, "inf") {
			counter = -1

			if game_state.state == .Selected_Figure {
				game_state.current_figure.point_counter = counter
			}
		}
	}

	current_x = UI_PADDING + UI_MARGIN
	current_y += UI_LINE_HEIGHT

	// Sincronizar puntos
	{
		rl.GuiLabel({current_x, current_y, 80, UI_LINE_HEIGHT}, "Restart beat(s)")
		current_x += 100 + UI_PADDING
		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 60, UI_LINE_HEIGHT-UI_PADDING}, "X") {
			game_state.sync_points = true
		}
	}
}

render_figure_ui :: proc() {
	if game_state.state == .Selected_Figure {
		using game_state.figure_ui
		
		current_x : f32 = f32(rl.GetScreenWidth())-UI_PADDING - UI_MARGIN - 300 // posicion inicial
		current_y : f32 = UI_Y_POS

		rl.GuiPanel(UI_REAL_PANEL_DIM, "Figure Options")

		// TODO: UI para las notas
		rl.GuiLabel({current_x, current_y, 200, UI_LINE_HEIGHT}, "*GUI para mostrar notas:*")

		{
			rl.GuiLabel({current_x + 50, current_y, 5, UI_LINE_HEIGHT}, cstr_from_int(int(game_state.ui.n_sides)))
			current_x += 100 + UI_PADDING

			if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
				n_sides = min(n_sides + 1, 25)

				if game_state.state == .Selected_Figure {
					game_state.current_figure.n = n_sides
					n_notes = game_state.current_figure.notes
				}
			}
			current_x += UI_LINE_HEIGHT + UI_PADDING

			if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
				// TODO: permitir líneas? Habría un salto de 2 a 1 (no hay figuras de 2 lados
				n_sides = max(n_sides - 1, 3)

				if game_state.state == .Selected_Figure {
					game_state.current_figure.n = n_sides
					n_notes = game_state.current_figure.notes
				}
			}
			current_x += UI_LINE_HEIGHT + UI_PADDING
		}
	}
}

render_debug_info :: proc() {
	current_x : c.int = UI_MARGIN
	current_y : c.int = game_state.window_size.y - 5 * (UI_FONT_SIZE + UI_PADDING/2) - UI_MARGIN

	rl.DrawText(
		fmt.caprintf("state: %w\x00", game_state.state, context.temp_allocator),
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
		fmt.caprintf("time: %1.5f\x00", rl.GetFrameTime(), context.temp_allocator),
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
		fmt.caprintf("n figures: %d\x00", len(game_state.figures), context.temp_allocator),
		current_x, current_y,
		UI_FONT_SIZE,
		rl.WHITE
	)
}
