# Building a native Windows x64 game

Engine: Godot 4.7.1 stable (a copy of the editor binary is kept in `tools/`).
`export_presets.cfg` contains the "Windows Desktop" preset (x86_64, embedded PCK, tests/tools/docs excluded).

## A. Official release export (recommended)
Needs the Godot 4.7.1 export templates (about 1 GB, one-time): in the editor use
*Editor > Manage Export Templates > Download and Install*, or place the unpacked templates in
`%APPDATA%\Godot\export_templates\4.7.1.stable\`. Then:

```
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --export-release "Windows Desktop" build/JumpCircuit.exe
```

Result: a single self-contained `build/JumpCircuit.exe`.

## B. Template-free build (what `tools/make_build.bat` does)
Works on a machine that only has the editor binary. It packs the game data and ships it next to
the engine executable renamed to match, which Godot then boots straight into the game:

```
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --import
tools\Godot_v4.7.1-stable_win64.exe --headless --path . --export-pack "Windows Desktop" build/JumpCircuit.pck
copy tools\Godot_v4.7.1-stable_win64.exe build\JumpCircuit.exe
```

Ship `JumpCircuit.exe` + `JumpCircuit.pck` together. This is fully native and playable; the only
differences from (A) are file size (the editor binary is larger than a release template) and that
it is an editor-class binary rather than an optimised release template.

## Sharing with friends
Zip the `build/` folder. Everyone runs `JumpCircuit.exe`; see the README for hosting/joining races.
