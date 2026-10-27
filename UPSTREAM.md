# Upstream and local changes

Fork of https://github.com/V-Sekai/godot-pmx at
`783f23f6acbf3798d5de47c0166f18cc3cb77112` (MIT).
The original editor module files and copyright are retained. They are not built
by the runtime CMake target. Kaitai C++ runtime retains its separate MIT license
in `thirdparty/ksy/kaitai/LICENSE`.

This fork adds runtime PMX parsing through a host C API GDExtension, safe original
texture resolution, Godot skinned meshes, vertex/group morphs, physics metadata,
and Honkai-style toon/face/outline shaders. No character assets are included.

The checked-in generated parser has deliberate handwritten patches: UTF-8 and
UTF-16LE selection, Windows Unicode conversion, finite floats, bounded strings
and arrays, invalid header/enum rejection, and trailing/soft-body data checks.
Do not overwrite these files with generated output without porting and testing
these patches. No parser or Godot binding generator runs during compilation.

Limits: Windows x64, Godot 4.7 single precision; SDEF/QDEF use linear skinning;
vertex and flattened vertex-group morphs drive expressions. Bone/material/UV/
impulse morphs, append-transform constraints and PMX soft-body simulation are
not implemented. Existing rigid bodies and spring 6DOF joints are exported to
the host's Jolt integration. Nonzero PMX soft bodies are rejected explicitly.
Sphere/toon texture references are preserved but the custom renderer uses its
own lighting rather than reproducing authored MME effects. An authored face
SDF is not required: enhanced mode generates geometry/UV-based angular threshold,
nose and highlight helpers; the basic head-local field remains an opt-out
fallback. User FaceMap/SDF/LightMap/Ramp/highlight inputs and hair-only stencil
eye overlays are provided by the independent Godot runtime renderer.
