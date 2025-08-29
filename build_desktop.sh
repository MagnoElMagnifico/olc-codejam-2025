#!/bin/bash -eu

OUT_DIR="build/desktop"
COMPILER_FLAGS="-o:speed -strict-style -vet-unused -vet-unused-variables -vet-unused-imports -vet-shadowing -warnings-as-errors -vet-using-param -vet-tabs -vet-packages:game -vet-unused-procedures"
mkdir -p $OUT_DIR
odin build src/main_desktop -out:$OUT_DIR/game $COMPILER_FLAGS
cp -R ./assets/ ./$OUT_DIR/assets/
echo "Desktop build created in ${OUT_DIR}"

