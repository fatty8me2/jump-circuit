# Licences

## Game content
All code, levels, shaders, meshes (procedural), UI and audio in this repository were created for
Jump Circuit. There are **no third-party art, audio or code assets** in the project.
Audio is synthesised by `tools/gen_audio.py` (see `docs/AUDIO.md`).

## Engine and bundled components
* **Godot Engine 4.7.1** - MIT licence. Copyright (c) 2014-present Godot Engine contributors,
  (c) 2007-2014 Juan Linietsky, Ariel Manzur. https://godotengine.org/license
* **Jolt Physics** (built into Godot 4.7) - MIT licence. Copyright (c) Jorrit Rouwe.
* **ENet** (networking, built into Godot) - MIT licence. Copyright (c) Lee Salzman.
* **miniupnpc** (UPnP, built into Godot) - BSD 3-clause. Copyright (c) Thomas Bernard.
* UI text uses Godot's bundled default font (Open Sans, SIL Open Font License 1.1).

Godot's full third-party notice list: https://docs.godotengine.org/en/stable/about/complying_with_licenses.html
A distributed build must include the Godot licence text; `build/` ships a copy of this file for that purpose.
