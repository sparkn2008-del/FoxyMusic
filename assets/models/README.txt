Optional true 3D fox (GLB / GLTF)
===============================

For a real 3D character (Blender, Mixamo, etc.), export:

  foxy_splash.glb

with animations named roughly:

  sleep   — curled idle loop (optional)
  wake    — stand up transition
  run     — side-view run cycle facing +X (right)

Place the file here, then wire it in the app (model_viewer or similar).
Until then, the built-in procedural 3D-style fox in lib/foxy_startup_splash.dart runs automatically.

Recommended: rigged fox, low poly (< 30k tris), PBR or flat black/white materials to match the splash.
