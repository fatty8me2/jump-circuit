@echo off
rem Template-free native build: see docs/BUILD.md
cd /d "%~dp0.."
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --export-pack "Windows Desktop" build/JumpCircuit.pck
copy /y tools\Godot_v4.7.1-stable_win64.exe build\JumpCircuit.exe >nul
copy /y docs\LICENSES.md build\LICENSES.md >nul
echo Build ready in build\
