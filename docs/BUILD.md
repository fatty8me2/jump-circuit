# Building a native Windows x64 game

Engine: Godot 4.7.1 stable. The editor binary is not in git (it is too large): download
`Godot_v4.7.1-stable_win64.exe` from godotengine.org and place it at `tools\Godot_v4.7.1-stable_win64.exe`.
`export_presets.cfg` contains the "Windows Desktop" preset (x86_64, embedded PCK, tests/tools/docs excluded).

## A. Official release export (recommended)
Needs the Godot 4.7.1 export templates (about 1 GB, one-time): in the editor use
*Editor > Manage Export Templates > Download and Install*, or place the unpacked templates in
`%APPDATA%\Godot\export_templates\4.7.1.stable\`. Then:

```
mkdir build
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --export-release "Windows Desktop" build/JumpCircuit.exe
```

Result: a single self-contained `build/JumpCircuit.exe`.

## B. Template-free build (what `tools/make_build.bat` does)
Works on a machine that only has the editor binary. It packs the game data and ships it next to
the engine executable renamed to match, which Godot then boots straight into the game:

```
mkdir build
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --export-pack "Windows Desktop" build/JumpCircuit.pck
copy tools\Godot_v4.7.1-stable_win64.exe build\JumpCircuit.exe
```

Godot refuses to export into a folder that does not exist, hence the `mkdir build`.
`make_build.bat` creates the folder itself, and stops with `BUILD FAILED` (exit code 1) if any step
fails, deleting the old `.pck` and `.exe` first so a failed export never ships a stale one.
`run.bat` in the repo root plays whatever build is in `build\` (route A or B); with no build it runs
the project from source using the editor binary in `tools\`.

Ship `JumpCircuit.exe` + `JumpCircuit.pck` together. This is fully native and playable; the only
differences from (A) are file size (the editor binary is larger than a release template) and that
it is an editor-class binary rather than an optimised release template.

## Sharing with friends
Zip the `build/` folder. Everyone runs `JumpCircuit.exe`; see the README for hosting/joining races.
