package game

// ==== IMPORTS ===============================================================

import rl "vendor:raylib"

import "core:math/linalg"
import "core:log"
import "core:fmt"
import "core:c"
import "core:strconv"
import "core:strings"
import "core:math"

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
	2 * UI_LINE_HEIGHT
}

CAMERA_ZOOM_SPEED :: 0.25
CAMERA_ZOOM_MIN :: 0.25
CAMERA_ZOOM_MAX :: 3.0

// ==== GAME DATA =============================================================

game_state: Game_State
Game_State :: struct {
	run: bool, // Determina si seguir ejecutando el game loop

	state: State,
	figures: [dynamic]Regular_Figure,
	current_figure: Regular_Figure,

	ui: UI_State,
	camera: Camera,
}

Camera :: struct {
	zoom: f32,
	position: v2,
	start_pos: v2,
	offset: v2,
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

Vertice :: struct {
	center: v2,
	radius: int,
}

// Figuras regulares: todos sus lados son iguales
Regular_Figure :: struct {
	center: v2,
	radius: v2,
	n: uint,
	vertices: [dynamic]Vertice
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
	game_state.camera.zoom = 1.0
	game_state.ui.n_sides = 3
	set_text_to_number(game_state.ui.sides_text[:], game_state.ui.n_sides)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_SIZE.x, WINDOW_SIZE.y, WINDOW_NAME)
}

// ==== GAME UPDATE ===========================================================

update :: proc() {
	// ==== GAME INPUT HANDLING ===============================================
	// Máquina de estados
	switch game_state.state {
		case .View: {
			using game_state

			if !rl.CheckCollisionPointRec(rl.GetMousePosition(), UI_PANEL_DIM) && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				log.info("Creación de una figura")

				current_figure.center = rl.GetMousePosition() / camera.zoom - camera.position
				current_figure.n = game_state.ui.n_sides

				// Evita que la figura haga flash si solo se hace un click
				current_figure.radius = current_figure.center

				state = .New_Figure
			}

			// ==== Camera movement ====
			if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
				camera.start_pos = rl.GetMousePosition()
			}

			if rl.IsMouseButtonDown(rl.MouseButton.MIDDLE) {
				camera.offset = (rl.GetMousePosition() - camera.start_pos) / camera.zoom
			}

			if rl.IsMouseButtonReleased(rl.MouseButton.MIDDLE) {
				camera.position += camera.offset
				camera.offset = {}
			}

			// ==== Camera zoom ====
			mouse_wheel := rl.GetMouseWheelMove()
			if mouse_wheel != 0 {
				mouse_pos := rl.GetMousePosition()
				camera.zoom = linalg.clamp(camera.zoom + mouse_wheel * CAMERA_ZOOM_SPEED, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
			}

			// TODO: transición a .Selected_Figure
		}

		case .New_Figure: {
			using game_state.current_figure

			if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
				// TODO: para que sean números enteros, aquí hay que hacer
				// cálculos para que coincida bien
				radius = (rl.GetMousePosition() / game_state.camera.zoom - game_state.camera.position)
			} \

			// Si la figura es muy pequeña, salir
			else if linalg.vector_length(center - radius) < MIN_FIG_RADIUS {
				game_state.state = .View
			} \

			// De lo contrario, añadir a la lista
			else {
				append(&game_state.figures, game_state.current_figure)
				log.info("Figura creada en", game_state.current_figure.center)
				log.info(radius)
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
		
		log.info(rotation)

		// TODO: si usamos esto, no tenemos una lista de puntos luego que
		// interpolar, lo que puede causar que no vayan bien sincronizados.
		// Problema para luego.
		rl.DrawPolyLines(
			(center + game_state.camera.position + game_state.camera.offset) * game_state.camera.zoom,
			sides = c.int(n),
			radius = linalg.vector_length(diff) * game_state.camera.zoom,
			rotation = rotation,
			color = rl.RED
		)

		for i:=0; i < int(n); i+=1{
			rl.DrawCircleLines(
				cast(i32) (center.x-(diff.x*math.cos_f32(math.to_radians(360*f32(i)/f32(n)))-math.sin_f32(math.to_radians(360*f32(i)/f32(n)))*diff.y)),
				cast(i32) (center.y-(diff.x*math.sin_f32(math.to_radians(360*f32(i)/f32(n)))+math.cos_f32(math.to_radians(360*f32(i)/f32(n)))*diff.y)),
				5.0,
				color = rl.RED
			)
		}

			
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
			(f.center + game_state.camera.position + game_state.camera.offset) * game_state.camera.zoom,
			sides = c.int(f.n),
			radius = linalg.vector_length(diff) * game_state.camera.zoom,
			rotation = rotation,
			color = rl.WHITE
		)

		//(centerX, centerY: c.int, radius: f32, color: Color)
		for i:=0; i < int(f.n); i+=1{
			x:=cast(i32) (f.center.x-(diff.x*math.cos_f32(math.to_radians(360*f32(i)/f32(f.n)))-math.sin_f32(math.to_radians(360*f32(i)/f32(f.n)))*diff.y))
			y:=cast(i32) (f.center.y-(diff.x*math.sin_f32(math.to_radians(360*f32(i)/f32(f.n)))+math.cos_f32(math.to_radians(360*f32(i)/f32(f.n)))*diff.y))
			rl.DrawCircleLines(
				x,
				y,
				5.0,
				color = rl.WHITE
			) //de momento solo es un dibujo
			v:=  Vertice{
				center = v2{cast(f32)x, cast(f32)y},
				radius = 5
			}
			//append(&f.vertices, v) //FIXME: por qué sale ese error, no lo entiendo
		}

		

	}

	// Render UI: debe ejecutarse después de las figuras para que se muestre por
	// encima.
	// TODO: customizar estilos, se ve bastante como la caca
	{
		using game_state.ui

		// Para la UI de más adelante
		current_x : f32 = UI_PADDING + UI_MARGIN // posicion inicial

		panel := UI_PANEL_DIM
		panel.height /= 2
		rl.GuiPanel(panel, "Figure Options")

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

	// Debug info
	{
		rl.DrawText(
			fmt.caprintf("time: %1.5f\x00", rl.GetFrameTime(), context.temp_allocator),
			0, WINDOW_SIZE.y - 50, 12, rl.WHITE)
		rl.DrawText(
			fmt.caprintf("zoom: %1.5f\x00", game_state.camera.zoom, context.temp_allocator),
			0, WINDOW_SIZE.y - 35, 12, rl.WHITE)
		rl.DrawText(
			fmt.caprintf("n figures: %d\x00", len(game_state.figures), context.temp_allocator),
			0, WINDOW_SIZE.y - 20, 12, rl.WHITE)
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
