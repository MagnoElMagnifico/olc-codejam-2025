package main_desktop

import "core:log"
import "core:os"
import "core:path/filepath"
import game ".."

main :: proc() {
	// Set working dir to dir of executable.
	// TODO: Esto se puede hacer solo en release, para testing es incómodo tener
	// que copiar todos los assets
	// Usar -define:<name>=<value>
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()
	
	game.init()

	for game.should_run() {
		game.update()
	}

	game.shutdown()
}
