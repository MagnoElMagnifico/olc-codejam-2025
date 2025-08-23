package game

import rl "vendor:raylib"
import "core:log"
import "core:fmt"
import "core:c"
import "core:strconv"
import "core:strings"

WINDOW_NAME :: "Synth Shapes"
WINDOW_SIZE :: [2]c.int {1280, 720}

game_state: Game_State
Game_State :: struct {
	run: bool // Determina si seguir ejecutando el game loop
}


text_Box_N_Side := rl.Rectangle({10, 135, 200, 20})
is_selected_text_Box_N_Side := false
sides_text : [dynamic]u8
char_count := 0

init :: proc() {
	game_state.run = true

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, WINDOW_NAME)

	append(&sides_text, 0) // null terminator
}

update :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground({0, 120, 153, 255})

	if (rl.CheckCollisionPointRec(rl.GetMousePosition(), text_Box_N_Side)) {
		rl.SetMouseCursor(rl.MouseCursor.IBEAM)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			is_selected_text_Box_N_Side = true
		}
	} else {
		rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			is_selected_text_Box_N_Side = false
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
	
	if is_selected_text_Box_N_Side {
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

	rl.DrawRectangleRec(text_Box_N_Side, rl.DARKGRAY)

	rl.GuiLabel({10, 120, 200, 20}, "Side amount:")
	rl.DrawText("Sides:", 10, 140, 5, rl.WHITE)
	rl.DrawText(cast(cstring) &sides_text[0], 40, 140, 5, rl.WHITE)

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
