#!/bin/bash -eu

# ==== FLAGS ==================================================================
#
# Point this to where you installed emscripten. Optional on systems that already
# have `emcc` in the path.
EMSCRIPTEN_SDK_DIR="$HOME/Downloads/emsdk/"
OUT_DIR="build/web"
COMPILER_FLAGS="-o:speed -strict-style -vet-unused -vet-unused-variables -vet-unused-imports -vet-shadowing -warnings-as-errors -vet-using-param -vet-tabs -vet-packages:game -vet-unused-procedures"

# Note RAYLIB_WASM_LIB=env.o -- env.o is an internal WASM object file. You can
# see how RAYLIB_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin.
#
# The emcc call will be fed the actual raylib library file. That stuff will end
# up in env.o
#
# Note that there is a rayGUI equivalent: -define:RAYGUI_WASM_LIB=env.o
WEB_FLAGS="-target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -define:RAYGUI_WASM_LIB=env.o"

# index_template.html contains the javascript code that calls the procedures in
# source/main_web/main_web.odin
EMCC_FLAGS="-sUSE_GLFW=3 -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS --shell-file src/main_web/index_template.html --preload-file assets -sEXPORTED_RUNTIME_METHODS=HEAPF32"
 
# =============================================================================

mkdir -p $OUT_DIR

# Compile Odin
odin build src/main_web -out:$OUT_DIR/game.wasm.o $COMPILER_FLAGS $WEB_FLAGS

# Copy JS for Odin
ODIN_PATH=$(odin root)
cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

# Setup emscripten
export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

# Compile with emscripten
# For debugging: Add `-g` to `emcc` (gives better error callstack in chrome)
FILES="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a ${ODIN_PATH}/vendor/raylib/wasm/libraygui.a"
emcc -o $OUT_DIR/index.html $FILES $EMCC_FLAGS

# Cleanup
rm $OUT_DIR/game.wasm.o
echo "Web build created in ${OUT_DIR}"

