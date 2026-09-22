@echo off
setlocal
rem Template-free native build: see docs/BUILD.md
rem Stops with BUILD FAILED (exit code 1) if any step fails, and never leaves an old .pck behind.
cd /d "%~dp0.."
set "GODOT=tools\Godot_v4.7.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7.1 editor binary not found at %GODOT%
  echo Download Godot_v4.7.1-stable_win64.exe from godotengine.org and put it in tools\
  goto fail
)
if not exist build mkdir build || goto fail
if not exist build\.gdignore type nul > build\.gdignore
if exist build\JumpCircuit.pck del /q build\JumpCircuit.pck
"%GODOT%" --headless --path . --import
if errorlevel 1 goto fail
"%GODOT%" --headless --path . --export-pack "Windows Desktop" build/JumpCircuit.pck
if errorlevel 1 goto fail
if not exist build\JumpCircuit.pck goto fail
copy /y "%GODOT%" build\JumpCircuit.exe >nul || goto fail
copy /y docs\LICENSES.md build\LICENSES.md >nul || goto fail
echo Build ready in build\
exit /b 0

:fail
echo BUILD FAILED - see output above
pause
exit /b 1
