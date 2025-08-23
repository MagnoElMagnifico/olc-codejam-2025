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

	current_state: State,
	figure: Regular_Figure,
}


State :: enum {
	Nothing = 0, // Default
	penis
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

// ==== GAME INIT =============================================================

init :: proc() {
	game_state.run = true

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, WINDOW_NAME)

	append(&sides_text, 0) // null terminator
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// ==== GAME INPUT HANDLING ===============================================
	{ // GUI tests
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
	}

	// Figure creation
	{
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			game_state.figure.center = rl.GetMousePosition()
		}

		if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
			game_state.figure.radius = rl.GetMousePosition()
		}
	}


	// ==== RENDER ============================================================
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({0, 120, 153, 255})

	rl.DrawRectangleRec(textbox_n_sides, rl.DARKGRAY)

	rl.GuiLabel({10, 120, 200, 20}, "Side amount:")
	rl.DrawText("Sides:", 10, 140, 5, rl.WHITE)
	rl.DrawText(cast(cstring) &sides_text[0], 40, 140, 5, rl.WHITE)

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
			sides = 4,
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
