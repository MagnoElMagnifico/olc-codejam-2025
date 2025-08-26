package game

import rl "vendor:raylib"

import "core:c"
import "core:fmt"
import "core:log"

MAX_SIDES :: 25

UI_PADDING     :: 5
UI_LINE_HEIGHT :: 30
UI_MARGIN      :: 15
UI_FONT_SIZE   :: 12
UI_BUTTON_SIZE :: UI_LINE_HEIGHT - UI_PADDING

// Tamaño del panel UI para dar a raylib
// TODO: mismo ancho en estos tamaños para que todo vaya alineado?
UI_PANEL_DIM :: rect {
	UI_MARGIN, UI_MARGIN,
	/* MAX ANCHO: text: */ 100 + /* 2 botones iguales: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + /* botón extra*/ 40,
	/* ALTO: cabecera + 4 filas + padding final */ 5 * UI_LINE_HEIGHT + UI_PADDING,
}

// Igual que antes pero para el panel de la figura
// TODO: poner esto al lado derecho de la pantalla implica saber el tamaño de la
// pantalla, por lo que no se puede poner aquí como constante.
UI_FIGURE_PANEL_DIM :: rect {
	UI_MARGIN, UI_PANEL_DIM.y + UI_PANEL_DIM.height + UI_MARGIN,
	/* text: */ 100 + /* 3 botones: */ 2*UI_LINE_HEIGHT + (2*2+1)*UI_PADDING + 40,
	5 * UI_LINE_HEIGHT + UI_PADDING,
}

// Se usa para determinar las propiedades de nuevas figuras
UI_Create_State :: struct {
	n_sides: uint,
	counter: int,
}

// NOTE: No hace falta, porque se lee de la figura seleccionada actual
/*UI_Figure_State :: struct{
	n_sides: uint,
	n_notes: [dynamic]uint,
}*/

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
			n_sides = min(n_sides + 1, MAX_SIDES)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			// TODO: permitir líneas?
			// Habría un salto de 2 a 1 (no hay figuras de 2 lados)
			// No, sería el número de puntos, no de lados, pero aún así se
			// necesitaría manejar el caso especial de líneas
			n_sides = max(n_sides - 1, 3)
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
				// TODO: resetear contador también?
			} else {
				for &f in game_state.figures {
					f.point_seg_index = 0
					f.point_progress = 0
					// TODO: resetear contador también?
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
	
	rl.GuiPanel(UI_FIGURE_PANEL_DIM, "Figure Options")
	current_x : f32 = UI_FIGURE_PANEL_DIM.x + UI_PADDING
	// f32(rl.GetScreenWidth())-UI_PADDING - UI_MARGIN - 300
	current_y : f32 = UI_FIGURE_PANEL_DIM.y + UI_LINE_HEIGHT

	using game_state.current_figure

	// TODO: UI para las notas
	rl.GuiLabel({current_x, current_y, 200, UI_LINE_HEIGHT}, "*GUI para mostrar notas:*")
	current_y += UI_LINE_HEIGHT

	// Número de lados de la figura
	{
		rl.GuiLabel({current_x, current_y, 50, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, current_y, 45, UI_LINE_HEIGHT}, cstr_from_int(int(n)))
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "+") {
			n = min(n + 1, MAX_SIDES)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, UI_LINE_HEIGHT-UI_PADDING, UI_LINE_HEIGHT-UI_PADDING}, "-") {
			n = max(n - 1, 3)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	current_x = UI_FIGURE_PANEL_DIM.x + UI_PADDING
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

	current_x = UI_FIGURE_PANEL_DIM.x + UI_PADDING
	current_y += UI_LINE_HEIGHT

	// Borrar figura
	{
		rl.GuiLabel({current_x, current_y, 80, UI_LINE_HEIGHT}, "Delete")
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, current_y+UI_PADDING/2, 60, UI_BUTTON_SIZE}, "X") {
			delete_current_figure()
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
