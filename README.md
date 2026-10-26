# Honkai MMD Loader

Runtime MMD PMX loading and Honkai-style rendering for the [Honkai Render application](https://github.com/furinasdog/Honkai-Style-RealTime-Rendering).

This is a modified fork of [V-Sekai/godot-pmx](https://github.com/V-Sekai/godot-pmx). It reuses the existing C++ parser, but runs through a standard Godot GDExtension instead of requiring a custom engine build. Original copyright and MIT licenses are retained. See [UPSTREAM.md](UPSTREAM.md) for the pinned revision, changes and supported features; the historical editor-module instructions are in [UPSTREAM_README.md](UPSTREAM_README.md).

## Integration

The host adds this directory with CMake `add_subdirectory`, links `pmx_parser`, and embeds `runtime/native_bridge.inl` in its raw C API bridge. The host supplies the `Value`/ABI helpers and registers `NativePmxReader.read_file()` and `get_error()`; see the application `native/src/godot_bridge.cpp`. This integration keeps one application DLL and does not use godot-cpp or a binding generator. This repository is not a standalone precompiled Godot addon.

The runtime `HonkaiPMXLoader.load_file(path, verified_archive_index)` builds a `Node3D`, `Skeleton3D`, skinned `ArrayMesh`, original shared textures and relative vertex blend shapes. It returns `{root, metadata}` or an empty dictionary with `error`. The application owns the returned node and installs it transactionally, after mapping validation. Textures must remain inside the verified archive root.

`HonkaiMMDMaterials.apply(root, metadata)` installs the toon and outline shaders. It preserves texture UVs, source diffuse colors, single/double-sided surfaces and material boundaries. The face uses a head-local shadow field; hair uses a stylized highlight; outlines preserve PMX per-vertex width and optional source colors. Character assets and game shaders are not included.

The face shadow is a two-tone field, independent of lip/nose/chin surface normals and view-dependent rim lighting. Tonal boundaries use only a screen-pixel antialiasing transition, avoiding a soft lower-face "beard" under high lights or mouth morphs. Clothing and hair keep their toon normal bands; authored texture colors are preserved.

Runtime material colors preserve PMX linear diffuse values and the linear toon palette when passed through Godot's Color conversion. Body lighting combines normal visibility and cast-shadow attenuation before one binary ramp. The loader also preserves authored PMX bone tail offsets in `pmx_tail_offsets` skeleton metadata so host retargeters can resolve terminal finger axes without assuming a local Y axis.

`set_shadows_enabled(false)` bypasses computed normal, cast and face-field shadows for every material. Source texture colors, UVs, alpha and outlines remain; newly applied models inherit the current setting. Re-enable it to restore toon lighting.

## Build and validation

Windows x64, C++17, CMake 3.20+, standard single-precision Godot 4.7. Tested with Visual Studio 2026. GCC/Clang and other platforms have not been validated.

Build the host with `BUILD_NATIVE_TESTS=ON` and run `pmx_parser_test`. Its Godot tests cover ZIP-to-native import, triangle counts, Unicode names, malformed input, expressions and opposing front/back materials. Private character regression assets are supplied locally, never committed.

SDEF/QDEF currently use Godot linear skinning; advanced MMD constraints, non-vertex morphs and soft-body physics have limits documented in UPSTREAM.md. The custom toon renderer approximates the visual style and does not reproduce every MME effect or game shader.
