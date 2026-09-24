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

## Releasing an update (players get prompted)
On launch the game asks GitHub for the latest release of `fatty8me2/jump-circuit`
(`autoload/updater.gd`). If that release's tag is a higher version than the running build's
`application/config/version` (in `project.godot`), the main menu shows an **Update available**
prompt with the release notes. *Install & Restart* downloads the versioned Windows ZIP directly,
checks its size and GitHub SHA-256 digest, installs the executable and game data beside the running
client, then launches the new version. *Remind Me Later* asks again next launch, and *Skip This
Version* stays quiet until an even newer release. Offline or rate-limited update checks are skipped;
the game never waits on them.

Players on versions before **1.2.2** need to install that version once from its release ZIP. Those
older clients only know how to open the release page; after 1.2.2 is installed, later updates install
from inside the game.

To ship an update:
1. Bump `config/version` in `project.godot` (e.g. `1.1.0` -> `1.2.0`).
2. Build (`tools\make_build.bat`) and zip `JumpCircuit.exe`, `JumpCircuit.pck`, and `LICENSES.md`
   at the root of the archive. Name it `JumpCircuit-vVERSION.zip` (for example,
   `JumpCircuit-v1.2.0.zip`).
3. Publish a release whose tag is that version with a `v` prefix, attaching the zip. The release
   body becomes the "what's new" text in the prompt:
   ```
   gh release create v1.2.0 JumpCircuit-v1.2.0.zip --title "Jump Circuit 1.2.0" --notes "What changed..."
   ```
Only **published, non-draft, non-prerelease** releases count, and only tags containing a version
number (`v1.2.0`, `1.2`, `jump-circuit-v1.2.0`). Test builds tagged without a version
(e.g. `jump-circuit-multiplayer-2026-09-23`) never trigger the prompt. Progress and settings live in
`%APPDATA%\Godot\app_userdata\Jump Circuit\`, so replacing the game folder keeps them.
Launch with `-- --no-update-check` to skip the check.
