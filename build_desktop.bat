@echo off

set OUT_DIR=build\desktop
set COMPILER_FLAGS=-o:speed -strict-style -vet-unused -vet-unused-variables -vet-unused-imports -vet-shadowing -warnings-as-errors -vet-using-param -vet-tabs -vet-packages:game -vet-unused-procedures
if not exist %OUT_DIR% mkdir %OUT_DIR%

odin build src\main_desktop -out:%OUT_DIR%\game.exe %COMPILER_FLAGS%
IF %ERRORLEVEL% NEQ 0 exit /b 1

xcopy /y /e /i assets %OUT_DIR%\assets >nul
IF %ERRORLEVEL% NEQ 0 exit /b 1

echo Desktop build created in %OUT_DIR%
