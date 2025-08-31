package game

import rl "vendor:raylib"
import "core:math/linalg"

CAMERA_ZOOM_SPEED :: 0.25
CAMERA_ZOOM_MIN :: 0.1
CAMERA_ZOOM_MAX :: 3.0

Camera :: struct {
	zoom: f32,
	position: v2,

	// Para mover la cámara, se almacena la posición antes de moverse y luego se
	// actualiza el offset.
	// Estas coordenadas están en screen space.
	start_pos: v2,
	offset: v2,
}


// Convierte un vector con coordenadas del mundo a coordenadas de pantalla
// Usar siempre antes de dibujar algo en la pantalla para que la camara funcione
// correctamente.
to_screen :: #force_inline proc "contextless" (camera: Camera, v: v2) -> v2 {
	// El centro del zoom será el centro de la pantalla
	focus := v2 { f32(game_state.window_size.x) / 2, f32(game_state.window_size.y) / 2 }

	// https://rexthony.medium.com/how-panning-and-zooming-work-in-a-2d-top-down-game-ab00c9d05d1a
	pan := v - camera.position - camera.offset
	zoom := camera.zoom * pan - focus * (camera.zoom - 1)

	return zoom
}


// Convierte un vector con coordenadas la pantalla (posición del ratón) a
// coordenadas de mundo
to_world :: #force_inline proc "contextless" (camera: Camera, v: v2) -> v2 {
	focus := v2 { f32(game_state.window_size.x) / 2, f32(game_state.window_size.y) / 2 }
	// v = z * pan - focus * (z - 1)
	// v / z = pan - focus * (z - 1) / z
	// pan = v / z + focus * (z - 1) / z
	// pan = (v + focus * (z - 1)) / z

	undo_zoom := (v + focus * (camera.zoom - 1)) / camera.zoom
	undo_pan := undo_zoom + camera.position + camera.offset
	return undo_pan
}


update_camera :: proc() {
	using game_state.camera
	// ==== Camera movement ====
	if rl.IsMouseButtonPressed(.MIDDLE) {
		start_pos = rl.GetMousePosition()
	}

	if rl.IsMouseButtonDown(.MIDDLE) {
		offset = (start_pos - rl.GetMousePosition()) / zoom
	}

	if rl.IsMouseButtonReleased(.MIDDLE) {
		position += offset
		offset = {}
	}

	// ==== Camera zoom ====
	mouse_wheel := rl.GetMouseWheelMove()
	if mouse_wheel != 0 {
		zoom = linalg.clamp(zoom + mouse_wheel * CAMERA_ZOOM_SPEED, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	}
}


