@echo off
setlocal
rem Plays the last build in build\ (tools\make_build.bat makes it); without one, runs the
rem project from source with the Godot 4.7.1 editor binary in tools\ if it is there.
set "ROOT=%~dp0"
set "GODOT=%ROOT%tools\Godot_v4.7.1-stable_win64.exe"
if exist "%ROOT%build\JumpCircuit.exe" if exist "%ROOT%build\JumpCircuit.pck" (
  start "" "%ROOT%build\JumpCircuit.exe"
  exit /b 0
)
if exist "%GODOT%" (
  if not exist "%ROOT%.godot\imported\" (
    echo First run: importing assets...
    "%GODOT%" --headless --path "%ROOT%." --import
  )
  start "" "%GODOT%" --path "%ROOT%."
  exit /b 0
)
echo No build found in build\ and no Godot 4.7.1 binary in tools\.
echo Build the game with tools\make_build.bat ^(see docs\BUILD.md^), or open the project in Godot 4.7.1 and press F5.
pause
exit /b 1
