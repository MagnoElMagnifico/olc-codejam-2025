package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"

import "core:math/linalg"
import "core:log"
import "core:fmt"
import "core:c"
import "core:strconv"
import "core:strings"

// ==== CONSTANTS =============================================================

// Definiciones de tipos comunes (por comodidad)
iv2 :: [2]c.int
v2 :: rl.Vector2     // [2]f32
rect :: rl.Rectangle // { x, y, width, height: f32 }

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}

MIN_FIG_RADIUS :: 3.0

UI_PADDING     : f32 : 3
UI_LINE_HEIGHT : f32 : 30
UI_MARGIN      :     : 10
UI_Y_POS       :     : 20 + UI_MARGIN

// Tamaño del panel UI
UI_PANEL_DIM :: rect {
	UI_MARGIN,
	UI_MARGIN,
	/* text: */ 100 + /* 2 botones: */ 2*UI_LINE_HEIGHT + 3*UI_PADDING,
	UI_LINE_HEIGHT
}

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop

	state: State,
	figures: [dynamic]Regular_Figure,
	current_figure: Regular_Figure,

	ui: UI_State,
}

UI_State :: struct {
	n_sides: uint,
	// solo hacen falta dos dígitos + null terminator
	sides_text: [3]u8,
}

State :: enum {
	View = 0,
	New_Figure,
	Selected_Figure,
}

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,
}

// Convertir el numero actual a cstring para mostrarlo en la UI
set_text_to_number :: proc(buf: []u8, n: uint) {
	assert(len(buf) <= 3, "set_text only implemented for 2 digits")

	// Conversión de 1 dígito
	if n < 10 {
		buf[0] = u8(n + uint('0'))
		buf[1] = 0
		return
	}

	// Conversión de 2 dígitos
	buf[0] = u8(n/10 + uint('0'))
	buf[1] = u8(n%10 + uint('0'))
	buf[2] = 0
}

// ==== GAME INIT =============================================================

init :: proc() {
	game_state.run = true
	game_state.ui.n_sides = 3
	set_text_to_number(game_state.ui.sides_text[:], game_state.ui.n_sides)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, WINDOW_NAME)
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// ==== GAME INPUT HANDLING ===============================================
	// BUG: esto es bastante poco fiable
	if rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) {
		log.error("colision")
	}

	// Máquina de estados
	switch game_state.state {
		case .View: {
			using game_state

			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				log.info("Creación de una figura")

				current_figure.center = rl.GetMousePosition()
				current_figure.n = game_state.ui.n_sides

				// Evita que la figura haga flash si solo se hace un click
				current_figure.radius = current_figure.center

				state = .New_Figure
			}

			// TODO: transición a .Selected_Figure
		}

		case .New_Figure: {
			using game_state.current_figure

			if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
				// TODO: para que sean números enteros, aquí hay que hacer
				// cálculos para que coincida bien
				radius = rl.GetMousePosition()
			} \

			// Si la figura es muy pequeña, salir
			else if linalg.vector_length(center - radius) < MIN_FIG_RADIUS {
				game_state.state = .View
			} \

			// De lo contrario, añadir a la lista
			else {
				append(&game_state.figures, game_state.current_figure)
				log.info("Figura creada en", game_state.current_figure.center)
				game_state.state = .View
			}
		}

		case .Selected_Figure: {
			// TODO:
		}
	}

	// ==== RENDER ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({30, 30, 30, 255})

	// Render figure
	if game_state.state == .New_Figure {
		using game_state.current_figure
		diff := center - radius
		rotation := linalg.atan(diff.y / diff.x) * linalg.DEG_PER_RAD

		// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
		if diff.x > 0 do rotation += 180

		// TODO: si usamos esto, no tenemos una lista de puntos luego que
		// interpolar, lo que puede causar que no vayan bien sincronizados.
		// Problema para luego.
		rl.DrawPolyLines(
			center,
			sides = c.int(n),
			radius = linalg.vector_length(diff),
			rotation = rotation,
			color = rl.RED
		)
	}
	for f in game_state.figures {
		diff := f.center - f.radius
		rotation := linalg.atan(diff.y / diff.x) * linalg.DEG_PER_RAD

		// Tener en cuenta que atan() solo funciona en [-pi/2, pi/2]
		if diff.x > 0 do rotation += 180

		// TODO: si usamos esto, no tenemos una lista de puntos luego que
		// interpolar, lo que puede causar que no vayan bien sincronizados.
		// Problema para luego.
		rl.DrawPolyLines(
			f.center,
			sides = c.int(f.n),
			radius = linalg.vector_length(diff),
			rotation = rotation,
			color = rl.WHITE
		)
	}

	// Render UI: debe ejecutarse después de las figuras para que se muestre por
	// encima.
	// @ui
	{
		using game_state.ui

		// Para la UI de más adelante
		current_x : f32 = UI_PADDING + UI_MARGIN // posicion inicial

		// TODO: customizar estilos, se ve bastante como la caca
		rl.GuiPanel(UI_PANEL_DIM, "Figure Options")

		rl.GuiLabel({current_x, UI_Y_POS, 30, UI_LINE_HEIGHT}, "Sides:")
		rl.GuiLabel({current_x + 50, UI_Y_POS, 5, UI_LINE_HEIGHT},
			cstring(raw_data(game_state.ui.sides_text[:])))

		// añadir el width del elemento y padding para el siguiente
		current_x += 100 + UI_PADDING

		if rl.GuiButton({current_x, UI_Y_POS+5, UI_LINE_HEIGHT-10, UI_LINE_HEIGHT-10}, "+") {
			n_sides = min(n_sides + 1, 25)
			set_text_to_number(sides_text[:], n_sides)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING

		if rl.GuiButton({current_x, UI_Y_POS+5, UI_LINE_HEIGHT-10, UI_LINE_HEIGHT-10}, "-") {
			// TODO: permitir líneas? Habría un salto de 2 a 1 (no hay figuras de 2 lados
			n_sides = max(n_sides - 1, 3)
			set_text_to_number(sides_text[:], n_sides)
		}
		current_x += UI_LINE_HEIGHT + UI_PADDING
	}

	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
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
