package game

import rl "vendor:raylib"
import "core:log"

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
BUTTON_HIGHLIGHT_BORDER_COLOR :: color { 100, 100, 100, 255 }
BUTTON_HIGHLIGHT_TEXT_COLOR   :: color {   0,   0,   0, 255 }

// Cuando el ratón está encima, usa estos colores
BUTTON_HOVER_COLOR        :: rl.WHITE
BUTTON_HOVER_BORDER_COLOR :: rl.GRAY
BUTTON_HOVER_TEXT_COLOR   :: rl.BLACK

// Cuando el botón está desactivado
BUTTON_DISABLED_COLOR        :: rl.WHITE
BUTTON_DISABLED_BORDER_COLOR :: rl.GRAY
BUTTON_DISABLED_TEXT_COLOR   :: rl.BLACK

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

	return click && hover
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

widget_text_box :: proc(state: ^Uint_Text_Box) {}
