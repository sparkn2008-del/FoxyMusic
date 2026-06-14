FoxyMusic startup splash — frame assets for designers
======================================================

Black + glow-white startup: fox sleeps, wakes, runs RIGHT off-screen chasing melodies.

Drop transparent PNGs (white line-art or soft 3D render on alpha).
Recommended canvas: 1024×1024, fox centered, transparent background.
For true 3D, see assets/models/README.txt (GLB).

Required files
--------------
  sleep.png       — curled / sleeping fox (emblem or full body)
  awake.png       — standing alert fox, facing camera or slight 3/4
  run_01.png … run_06.png — side profile running cycle (loopable, facing RIGHT)
  music_star.png  — glowing eighth-note (optional; code draws one if missing)

Wake transition (used in app)
-----------------------------
  wake_01.png … wake_04.png — sleep → awake in-between poses

Naming must match exactly. After adding files, run: flutter pub get
Then rebuild the app. Placeholders are copies of foxy_splash.png until replaced.
