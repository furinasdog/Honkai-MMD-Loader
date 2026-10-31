# Honkai MMD Loader

Runtime MMD PMX loading and Honkai-style rendering for the [Honkai Render application](https://github.com/furinasdog/Honkai-Style-RealTime-Rendering).

This is a modified fork of [V-Sekai/godot-pmx](https://github.com/V-Sekai/godot-pmx). It reuses the existing C++ parser, but runs through a standard Godot GDExtension instead of requiring a custom engine build. Original copyright and MIT licenses are retained. See [UPSTREAM.md](UPSTREAM.md) for the pinned revision, changes and supported features; the historical editor-module instructions are in [UPSTREAM_README.md](UPSTREAM_README.md).

## Integration

The host adds this directory with CMake `add_subdirectory`, links `pmx_parser`, and embeds `runtime/native_bridge.inl` in its raw C API bridge. The host supplies the `Value`/ABI helpers and registers `NativePmxReader.read_file()` and `get_error()`; see the application `native/src/godot_bridge.cpp`. This integration keeps one application DLL and does not use godot-cpp or a binding generator. This repository is not a standalone precompiled Godot addon.

The runtime `HonkaiPMXLoader.load_file(path, verified_archive_index)` builds a `Node3D`, `Skeleton3D`, skinned `ArrayMesh`, original shared textures and relative vertex blend shapes. It returns `{root, metadata}` or an empty dictionary with `error`. The application owns the returned node and installs it transactionally, after mapping validation. Textures must remain inside the verified archive root.

Custom lighting-map assignments are saved by temporary-file replacement. A failed import or removal preserves the previous in-memory assignment and rendered material; the host can display `map_error` to the user.

`HonkaiMMDMaterials.apply(root, metadata)` installs the toon and outline shaders. It preserves texture UVs, source diffuse colors, single/double-sided surfaces and material boundaries. The face uses a head-local shadow field; hair uses a stylized highlight; outlines preserve PMX per-vertex width and optional source colors. Character assets and game shaders are not included.

The face shadow is a head-local field, independent of lip/nose/chin surface normals and view-dependent rim lighting. Enhanced normal bands use softness 0.025 and face SDF boundaries use 0.015, with a screen-derivative minimum for raster antialiasing. An eye-height mask restricts facial projected shadows to the upper face; skin below the head receives ordinary projected shadows. Authored texture colors and mesh normals are preserved.

Runtime material colors preserve PMX linear diffuse values and the linear toon palette when passed through Godot's Color conversion. The loader also preserves authored PMX bone tail offsets in `pmx_tail_offsets` skeleton metadata so host retargeters can resolve terminal finger axes without assuming a local Y axis.

Enhanced rendering defaults on: body, skin, hair and metal share half-Lambert and LightMap threshold rules and receive directional projected shadows, subject to the source receive-shadow flag. All characters use the same material rules; diffuse colors, outline pigments and character names do not select shadow corrections. There is no crown-normal replacement or neck/chest shadow exemption. Missing face/nose/highlight helpers are generated from the model geometry and UVs and cached by geometry fingerprint. These are approximate angular thresholds, not official artist-authored FaceMaps. `set_enhanced(false)` restores basic toon shading and original textures.

The host supplies Godot environment diffuse irradiance. LightMap R controls its ambient AO independently as `0.5 + 0.5 * R`; it also scales direct illumination before Ramp sampling. A supplied warm/cool Ramp takes precedence over PMX Toon. Without a Ramp, the authored Toon remains in use; without either, a shared material-category palette supplies the shadow tone. PMX Sphere multiplication and addition remain intact.

`material_slots` exposes stable IDs and source names. `import_custom_map(id, role, path)` accepts FaceMap, grayscale SDF, LightMap, warm/cool Ramp or grayscale highlight masks; `remove_custom_map` restores the fallback. Data maps use linear sampling, color Ramps use sRGB sampling. Imported images are copied into the current user's cache and assignments persist per model identity.

`set_eye_transparency(enabled, strength)` defaults off. Depth-tested hair stencil masks restrict a later eye-detail pass; foreground geometry still occludes the eye, with frontal-angle gating. External facial openings use a red-channel outline mask while authored alpha edge weights and morph topology remain intact. This needs the pinned Godot 4.7 stencil renderer; other renderer versions are not validated.

`set_shadows_enabled(false)` bypasses computed normal, cast and face-field shadows and suppresses environment lighting for every material. Source texture colors, additive Sphere output, UVs, alpha and outlines remain; newly applied models inherit the current setting. Re-enable it to restore toon lighting.

## Build and validation

Windows x64, C++17, CMake 3.20+, standard single-precision Godot 4.7. Tested with Visual Studio 2026. GCC/Clang and other platforms have not been validated.

Build the host with `BUILD_NATIVE_TESTS=ON` and run `pmx_parser_test`. Its Godot tests cover ZIP-to-native import, triangle counts, Unicode names, malformed input, expressions and opposing front/back materials. Private character regression assets are supplied locally, never committed.

SDEF/QDEF currently use Godot linear skinning; advanced MMD constraints, non-vertex morphs and soft-body physics have limits documented in UPSTREAM.md. The custom toon renderer approximates the visual style and does not reproduce every MME effect or game shader.
