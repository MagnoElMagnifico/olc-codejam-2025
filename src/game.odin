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
v2 :: rl.Vector2 // [2]f32
iv2 :: [2]c.int
rect :: rl.Rectangle

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: iv2 {1280, 720}

v2_to_iv2 :: proc(v: v2) -> iv2 {
	return {c.int(v.x), c.int(v.y)}
}

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop

	figure: Regular_Figure,
	n_sides: uint,
}

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,
}

// TODO: estos se pueden mover al game_state para que esté mejor ordenado
textbox_n_sides := rect {10, 135, 200, 20}
is_selected_textbox_n_side := false
sides_text : [dynamic]u8
char_count := 0

test_sides_text: [3]u8 // solo hacen falta dos dígitos + null terminator

// Convertir el numero actual a cstring para mostrarlo en la UI
update_test_sides_text :: proc(n: uint) {
	// Conversión de 1 dígito
	if n < 10 {
		test_sides_text[0] = u8(n + uint('0'))
		test_sides_text[1] = 0
		return
	}

	// Conversión de 2 dígitos
	test_sides_text[0] = u8(n/10 + uint('0'))
	test_sides_text[1] = u8(n%10 + uint('0'))
	test_sides_text[2] = 0
}

// ==== GAME INIT =============================================================

init :: proc() {
	game_state.run = true
	game_state.n_sides = 3
	update_test_sides_text(game_state.n_sides)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, WINDOW_NAME)

	append(&sides_text, 0) // null terminator
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// ==== GAME INPUT HANDLING ===============================================
	/*{
		if (rl.CheckCollisionPointRec(rl.GetMousePosition(), textbox_n_sides)) {
			rl.SetMouseCursor(rl.MouseCursor.IBEAM)
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				is_selected_textbox_n_side = true
			}
		} else {
			rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				is_selected_textbox_n_side = false
				if strconv.atoi(strings.string_from_ptr(&sides_text[0], len(sides_text))) < 2{
					char_count -= 1
					if char_count < 0 {
						char_count = 0
					} else {
						pop(&sides_text) // remove < 2 value
					}
					append(&sides_text, 0)
					sides_text[char_count] = 50 // null terminator
					char_count += 1
				}
				log.info(sides_text)
			}
		}
		
		if is_selected_textbox_n_side {
			value := rl.GetCharPressed()

			for value > 0 {
				if (value >= 48) && (value <= 57) && (char_count < 2) {
					append(&sides_text, 0)             // null terminator
					sides_text[char_count] = u8(value) // store character
					char_count += 1
				}
				value = rl.GetCharPressed()
			}

			if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
				char_count -= 1
				if char_count < 0 {
					char_count = 0
				} else {
					pop(&sides_text) // remove character
					sides_text[char_count] = 0 // null terminator
				}
			}
		}
	}*/

	PADDING : f32 : 3
	HEIGHT : f32 : 30
	MARGIN :: 10
	Y_POS :: 20 + MARGIN
	current_x : f32 = PADDING + MARGIN // posicion inicial

	// el ancho es el valor final de `current_x`, pero la función se debe
	// ejecutar primero para que se dibujen los botones por encima
	gui_panel_dim := rect {MARGIN, MARGIN, 100 + 2*HEIGHT + 3*PADDING, HEIGHT}

	// TODO: customizar estilos, se ve bastante como la caca

	rl.GuiPanel(gui_panel_dim, "Number of sides")

	rl.GuiLabel({current_x, Y_POS, 30, HEIGHT}, cstring(raw_data(test_sides_text[:])))
	current_x += 100 + PADDING // añadir el width del elemento y el padding

	using game_state
	if rl.GuiButton({current_x, Y_POS+5, HEIGHT-10, HEIGHT-10}, "+") {
		n_sides = min(n_sides + 1, 25)
		update_test_sides_text(n_sides)
	}
	current_x += HEIGHT + PADDING

	if rl.GuiButton({current_x, Y_POS+5, HEIGHT-10, HEIGHT-10}, "-") {
		// TODO: permitir líneas? Habría un salto de 2 a 1 (no hay figuras de 2 lados
		n_sides = max(n_sides - 1, 3)
		update_test_sides_text(n_sides)
	}
	current_x += HEIGHT + PADDING

	// Usar la UI no debe interferir con colocar figuras
	// TODO: esto no acaba de funcionar bien, la figura se sigue borrando
	// Idea: hacer el checkeo de la colisión dentro del if
	if !rl.CheckCollisionPointRec(rl.GetMousePosition(), gui_panel_dim) {
		using game_state.figure
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			center = rl.GetMousePosition()
		}

		if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
			radius = rl.GetMousePosition()
		}

		if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
			n = game_state.n_sides
		}
	}

	// ==== RENDER ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({30, 30, 30, 255})

	/*rl.DrawRectangleRec(textbox_n_sides, rl.DARKGRAY)
	rl.GuiLabel({10, 120, 200, 20}, "Side amount:")
	rl.DrawText("Sides:", 10, 140, 5, rl.WHITE)
	rl.DrawText(cast(cstring) &sides_text[0], 40, 140, 5, rl.WHITE)*/

	// Render figure
	{
		using game_state.figure
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
			color = rl.WHITE
		)

	}

	// Anything allocated using temp allocator is invalid after this.
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
