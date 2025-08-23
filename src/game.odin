package game

import rl "vendor:raylib"
import "core:log"
import "core:fmt"
import "core:c"
import "core:strconv"
import "core:strings"


run: bool
texture: rl.Texture
texture2: rl.Texture
texture2_rot: f32
text_Box_N_Side := rl.Rectangle({10, 135, 200, 20})
is_selected_text_Box_N_Side := false
sides_text : [dynamic]u8
char_count := 0


init :: proc() {
	run = true

	append(&sides_text, 0) // null terminator
	

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib on the web")

	// Anything in `assets` folder is available to load.
	texture = rl.LoadTexture("assets/round_cat.png")

	// A different way of loading a texture: using `read_entire_file` that works
	// both on desktop and web. Note: You can import `core:os` and use
	// `os.read_entire_file`. But that won't work on web. Emscripten has a way
	// to bundle files into the build, and we access those using this
	// special `read_entire_file`.
	if long_cat_data, long_cat_ok := read_entire_file("assets/long_cat.png", context.temp_allocator); long_cat_ok {
		long_cat_img := rl.LoadImageFromMemory(".png", raw_data(long_cat_data), c.int(len(long_cat_data)))
		texture2 = rl.LoadTextureFromImage(long_cat_img)
		rl.UnloadImage(long_cat_img)
	}


}

update :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground({0, 120, 153, 255})
	{
		texture2_rot += rl.GetFrameTime()*50
		source_rect := rl.Rectangle {
			0, 0,
			f32(texture2.width), f32(texture2.height),
		}
		dest_rect := rl.Rectangle {
			300, 220,
			f32(texture2.width)*5, f32(texture2.height)*5,
		}
		rl.DrawTexturePro(texture2, source_rect, dest_rect, {dest_rect.width/2, dest_rect.height/2}, texture2_rot, rl.WHITE)
	}
	rl.DrawTextureEx(texture, rl.GetMousePosition(), 0, 5, rl.WHITE)
	rl.DrawRectangleRec({0, 0, 220, 170}, rl.BLACK)
	rl.GuiLabel({10, 10, 200, 20}, "raygui works!")


	rl.GuiLabel({10, 120, 200, 20}, "Side amount:")

	

	if (rl.CheckCollisionPointRec(rl.GetMousePosition(), text_Box_N_Side)) {
		rl.SetMouseCursor(rl.MouseCursor.IBEAM)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			is_selected_text_Box_N_Side = true
		}
	}else{
		rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			is_selected_text_Box_N_Side = false
			if strconv.atoi(strings.string_from_ptr(&sides_text[0], len(sides_text))) < 2{
				char_count -= 1
				if char_count < 0 {
					char_count = 0
				}else{
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
				append(&sides_text, 0)               // null terminator
				sides_text[char_count] = u8(value)          // store character
				char_count += 1
			}
			value = rl.GetCharPressed()
		}

		if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
			char_count -= 1
			if char_count < 0 {
				char_count = 0
			}else{
				pop(&sides_text) // remove character
				sides_text[char_count] = 0 // null terminator
			}
		}
	}

	if rl.GuiButton({10, 30, 200, 20}, "Print to log (see console)") {
		log.info("log.info works!")
		fmt.println("fmt.println too.")
	}

	if rl.GuiButton({10, 60, 200, 20}, "Source code (opens GitHub)") {
		rl.OpenURL("https://github.com/karl-zylinski/odin-raylib-web")
	}

	if rl.GuiButton({10, 90, 200, 20}, "Quit") {
		run = false
	}

	rl.DrawRectangleRec(text_Box_N_Side, rl.DARKGRAY)

	rl.DrawText("Sides:", 10, 140, 5, rl.WHITE)
	rl.DrawText(cast(cstring) &sides_text[0], 40, 140, 5, rl.WHITE)


	rl.EndDrawing()

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
			run = false
		}
	}

	return run
}