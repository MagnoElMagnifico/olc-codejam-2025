package game

import rl "vendor:raylib"
import "core:fmt"
import "core:math"

// ==== Labels ====
LABEL_FONT_SIZE :: 12
LABEL_COLOR     :: color { 255, 255, 255, 255 }
LABEL_SPACING   :: 2

// ==== Panel ====
PANEL_HEADER_PADDING :: 2.0
PANEL_HEADER_COLOR :: color { 150, 150, 150, 255 }
PANEL_BACK_COLOR   :: color { 100, 100, 100, 255 }
PANEL_BORDER_COLOR :: color {  50,  50,  50, 255 }
PANEL_BORDER_SIZE  :: 5.0
PANEL_LABEL_COLOR  :: LABEL_COLOR

// ==== Botones ====
BUTTON_BORDER_SIZE :: 3.0

// Por defecto se usan estos colores
BUTTON_COLOR        :: color { 255, 255, 255, 255 }
BUTTON_BORDER_COLOR :: color { 100, 100, 100, 255 }
BUTTON_TEXT_COLOR   :: color {   0,   0,   0, 255 }

// Cuando el botón está seleccionado o se pulsa se usa este color
BUTTON_HIGHLIGHT_COLOR        :: color { 255,   0,   0, 255 }
BUTTON_HIGHLIGHT_BORDER_COLOR :: color { 100,   0,   0, 255 }
BUTTON_HIGHLIGHT_TEXT_COLOR   :: color {   0,   0,   0, 255 }

// Cuando el ratón está encima, usa estos colores
BUTTON_HOVER_COLOR        :: color { 255, 255, 255, 255 }
BUTTON_HOVER_BORDER_COLOR :: color { 200,   0,   0, 255 }
BUTTON_HOVER_TEXT_COLOR   :: color {   0,   0,   0, 255 }

// Cuando el botón está desactivado
BUTTON_DISABLED_COLOR        :: color { 130, 130, 130, 255 }
BUTTON_DISABLED_BORDER_COLOR :: PANEL_BACK_COLOR
BUTTON_DISABLED_TEXT_COLOR   :: color {   0,   0,   0, 255 }

// ==== Slider ====
SLIDER_BORDER_SIZE  :: 3.0
SLIDER_FRONT_COLOR  :: color {   0,   0, 255, 255 }
SLIDER_BACK_COLOR   :: color { 100, 100, 100, 255 }
SLIDER_BORDER_COLOR :: color {   0,   0, 255, 255 }
SLIDER_TEXT_COLOR   :: color { 255, 255, 255, 255 }

Uint_Text_Box :: struct {
	value: uint,
	box: rect,
	selected: bool,
}

widget_panel :: proc(size: rect, name: cstring) {
	// Color de fondo
	rl.DrawRectangleRec(size, PANEL_BACK_COLOR)

	// Cabecera
	header := rect { size.x, size.y, size.width, LABEL_FONT_SIZE + 2*PANEL_HEADER_PADDING + 2*PANEL_BORDER_SIZE }
	rl.DrawRectangleRec(header, PANEL_HEADER_COLOR)

	// Borde
	rl.DrawRectangleLinesEx(size, PANEL_BORDER_SIZE, PANEL_BORDER_COLOR)

	// Texto de cabecera
	widget_label(
		position = {
			header.x + PANEL_HEADER_PADDING + PANEL_BORDER_SIZE,
			header.y + PANEL_HEADER_PADDING + PANEL_BORDER_SIZE,
			header.width  - 2 * PANEL_BORDER_SIZE,
			header.height - 2 * PANEL_BORDER_SIZE,
		},
		text = name,
		color = PANEL_LABEL_COLOR,
		hcenter = true,
	)

}

widget_button :: proc(
	size: rect,
	text: cstring,
	highlight := false,
	disabled := false,
) -> (clicked: bool) {

	mouse := rl.GetMousePosition()
	hover := rl.CheckCollisionPointRec(mouse, size)
	click := rl.IsMouseButtonPressed(.LEFT)

	background_color, border_color, text_color: color
	if disabled {
		background_color = BUTTON_DISABLED_COLOR
		border_color     = BUTTON_DISABLED_BORDER_COLOR
		text_color       = BUTTON_DISABLED_TEXT_COLOR

	} else if highlight || (click && hover) {
		background_color = BUTTON_HIGHLIGHT_COLOR
		border_color     = BUTTON_HIGHLIGHT_BORDER_COLOR
		text_color       = BUTTON_HIGHLIGHT_TEXT_COLOR

	} else if hover {
		background_color = BUTTON_HOVER_COLOR
		border_color     = BUTTON_HOVER_BORDER_COLOR
		text_color       = BUTTON_HOVER_TEXT_COLOR

	} else {
		background_color = BUTTON_COLOR
		border_color     = BUTTON_BORDER_COLOR
		text_color       = BUTTON_TEXT_COLOR
	}

	// Fondo del botón
	rl.DrawRectangleRec(size, background_color)
	// Borde
	rl.DrawRectangleLinesEx(size, BUTTON_BORDER_SIZE, border_color)
	// Texto
	widget_label(
		position = {
			size.x + BUTTON_BORDER_SIZE,
			size.y + BUTTON_BORDER_SIZE,
			size.width  - 2 * BUTTON_BORDER_SIZE,
			size.height - 2 * BUTTON_BORDER_SIZE,
		},
		text = text,
		color = text_color,
		hcenter = true,
	)

	return false if disabled else click && hover
}

widget_label :: proc(
	position: rect,
	text: cstring,
	color := LABEL_COLOR,
	hcenter := false,
) {
	// TODO: Cortar cuando se sale del tamaño dado?
	// BUG: esto devuelve 0
	text_size := rl.MeasureTextEx(
		font = game_state.ui.font,
		text = text,
		fontSize = LABEL_FONT_SIZE,
		spacing = LABEL_SPACING,
	)

	// HACK: esto es un apaño, pero tampoco funciona
	if text_size.x == 0 {
		// Asume proporción de cada letra 2 (alto) : 1 (ancho)
		text_size.x = f32(len(text)) * LABEL_FONT_SIZE/2
	}
	if text_size.y == 0 {
		text_size.y = LABEL_FONT_SIZE
	}

	// Centrar horizontalmente
	text_x := position.x
	if hcenter {
		text_x += position.width / 2 - text_size.x / 2
	}

	// Centrar verticalmente
	text_y := position.y + position.height / 2 - text_size.y / 2

	rl.DrawTextEx(
		font = game_state.ui.font,
		text = text,
		position = v2 { text_x, text_y },
		fontSize = LABEL_FONT_SIZE,
		spacing = LABEL_SPACING,
		tint = color,
	)
}

// Recibe el tamaño y el progreso actual [0, 1] y devuelve el progreso
// actualizado (igual que antes si no hay cambios, o con el porcentaje nuevo si
// el usuario lo cambió)
widget_slider :: proc(
	size: rect,
	current: f32,
	show_number := true,
) -> (new: f32) {
	assert(0.0 <= current && current <= 1.0, "current is not in [0,1]")
	new = current

	// No se puede poner al 100% y puede ser un poco frustrante, así que para el
	// chequeo dejar un poco más de margen
	size_check := size
	size_check.width += 2*SLIDER_BORDER_SIZE
	mouse := rl.GetMousePosition()
	hover := rl.CheckCollisionPointRec(mouse, size_check)
	click := rl.IsMouseButtonDown(.LEFT)
	if hover && click {
		new = (mouse.x - size.x) / size.width
		new = math.clamp(new, 0, 1)
	}

	// Fondo
	rl.DrawRectangleRec(size, SLIDER_BACK_COLOR)

	// Progreso
	progress_size := size
	progress_size.width = min(current * size.width, size.width)
	rl.DrawRectangleRec(progress_size, SLIDER_FRONT_COLOR)

	if show_number {
		widget_label(
			position = size,
			text = fmt.caprintf("  %2.1f %%", 100 * current, allocator = context.temp_allocator),
			color = SLIDER_TEXT_COLOR,
			hcenter = false,
		)
	}

	// Borde
	rl.DrawRectangleLinesEx(size, SLIDER_BORDER_SIZE, SLIDER_BORDER_COLOR)

	return
}

when false {
	// Devuelve true si se modificó
	widget_slider_number :: proc(
		size: rect,
		current: ^$T,
		minimum: T,
		maximum: T,
		show_number := true,
		fmt_str := "%w",
	) -> bool {
		assert(minimum < maximum, "invalid range")

		ease_log :: proc(x: f32) -> f32 {
			return 1 - math.pow(1 - x, 3)
		}
		inv_ease_log :: proc(x: f32) -> f32 {
			return 1 - math.pow(1 - x, 1.0/3.0)
		}

		// Progreso actual
		value := math.clamp(current^, minimum, maximum)
		progress := (value - minimum) / (maximum - minimum)
		progress = ease_log(progress)

		// Fondo
		rl.DrawRectangleRec(size, SLIDER_BACK_COLOR)

		// Dibujar la barra
		progress_size := size
		progress_size.width = min(progress * size.width, size.width)
		rl.DrawRectangleRec(progress_size, SLIDER_FRONT_COLOR)

		if show_number {
			widget_label(
				position = size,
				text = fmt.caprintf(fmt_str, value, allocator = context.temp_allocator),
				color = SLIDER_TEXT_COLOR,
				hcenter = false,
			)
		}

		// Borde
		rl.DrawRectangleLinesEx(size, SLIDER_BORDER_SIZE, SLIDER_BORDER_COLOR)

		// No se puede poner al 100% y puede ser un poco frustrante, así que para el
		// chequeo dejar un poco más de margen
		size_check := size
		size_check.width += 2*SLIDER_BORDER_SIZE
		mouse := rl.GetMousePosition()
		hover := rl.CheckCollisionPointRec(mouse, size_check)
		click := rl.IsMouseButtonDown(.LEFT)
		if hover && click {
			new_progress := (mouse.x - size.x) / size.width
			new_progress = inv_ease_log(new_progress)
			current^ = math.clamp(new_progress * (maximum - minimum) + minimum, minimum, maximum)
			return true
		}

		return false
	}
}

widget_number :: proc(
	text: cstring,
	number: ^$T,
	minimum, maximum: T,
	size: rect,
	step := 1,
	label := f32(0.5),
) {
	assert(step > 0, "step must be positive non-null number")

	// Button size
	button_size := size.height - UI_PADDING/2

	// Calcular el tamaño que le corresponde a cada parte del texto
	space_for_text := size.width - (2*2+1)*UI_PADDING - 2*button_size
	label_width := label * space_for_text
	number_width := (1 - label) * space_for_text

	// Dibujar label que indica qué es el valor a modificar
	x := size.x
	widget_label({x, size.y, label_width, size.height}, text)
	x += label_width + UI_PADDING

	// Dibujar el botón de restar
	if widget_button(
		text = "-",
		size = {x, size.y+UI_PADDING/2, button_size, button_size},
		disabled = number^ <= minimum,
	) {
		number^ = math.clamp(number^ - cast(T) step, minimum, maximum)
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	// Dibujar el valor actual
	widget_label(
		position = rect {x, size.y, number_width, button_size},
		text = cstr_from_int(int(number^)),
		hcenter = true,
	)
	x += number_width + UI_PADDING

	// Dibujar el botón para sumar
	if widget_button(
		text = "+",
		size = {x, size.y+UI_PADDING/2, button_size, button_size},
		disabled = number^ >= maximum,
	) {
		number^ = math.clamp(number^ + cast(T) step, minimum, maximum)
	}
}

widget_number_inf :: proc(
	text: cstring,
	number: ^$T,
	minimum, maximum: T,
	size: rect,
	step := 1,
	label := f32(0.5),
	inf := COUNTER_INF,
	inf_size := f32(1.5),
) {
	assert(step > 0, "step must be positive non-null number")

	button_size := size.height - UI_PADDING/2
	inf_button_size := inf_size * button_size
	new_size := size
	new_size.width -= inf_button_size + UI_PADDING

	widget_number(text, number, minimum, maximum, new_size, step, label)

	// Dibujar el botón de infinito sumar
	if widget_button(
		text = "inf",
		size = {
			size.x + size.width - inf_button_size - 3*UI_PADDING,
			size.y+UI_PADDING/2,
			inf_button_size, button_size,
		},
		disabled = number^ == COUNTER_INF,
	) {
		number^ = COUNTER_INF
	}
}

widget_enum :: proc(
	text: cstring,
	value: ^$T,
	enum_str: [T]cstring,
	size: rect,
	label := f32(0.5),
) {
	// Button size
	button_size := size.height - UI_PADDING/2

	// Calcular el tamaño que le corresponde a cada parte del texto
	space_for_text := size.width - (2*2+1)*UI_PADDING - 2*button_size
	label_width := label * space_for_text
	enum_width := (1 - label) * space_for_text

	// Dibujar label que indica qué es el valor a modificar
	x := size.x
	widget_label({x, size.y, label_width, size.height}, text)
	x += label_width + UI_PADDING

	// Dibujar el botón de restar
	if widget_button(
		text = "-",
		size = {x, size.y+UI_PADDING/2, button_size, button_size},
	) {
		value^ = cast(T) ((int(value^) - 1) %% len(T))
	}
	x += UI_BUTTON_SIZE + UI_PADDING

	// Dibujar el valor actual
	widget_label(
		position = rect {x, size.y, enum_width, button_size},
		text = enum_str[value^],
		hcenter = true,
	)
	x += enum_width + UI_PADDING

	// Dibujar el botón para sumar
	if widget_button(
		text = "+",
		size = {x, size.y+UI_PADDING/2, button_size, button_size},
	) {
		value^ = cast(T) ((int(value^) + 1) %% len(T))
	}
}
