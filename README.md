https://github.com/user-attachments/assets/a4ec87ea-d5f0-4d97-94c7-576e27f04fc7

# Droffel Music Studio

**A procedural music visualizer driven by a fixed fly-brain simulation.** Choose a track, let six audio roles stimulate a 165,122-state neural model, and export a developing 2D/3D motion-design scene as MP4.

Droffel Music Studio turns music into visual phrases instead of a repeating spectrum loop. Attacks prepare camera changes, bass bends mass, percussion cuts and opens surfaces, melodies reshape contours, and sustained sound holds the scene together.

## Features

- Phrase-level scene development with section changes and scored transitions.
- Fixed, deterministic neural simulation with cached projects.
- Mixed 2D/3D forms: folded panels, rounded solids, rings, tunnels and printed surfaces.
- Clean exports without editor controls or incidental text overlays.
- 4K UHD and 60 FPS MP4 export with constant frame timing.
- Optional compact brain overlay for exported videos.
- Local processing: selected audio, stems, recordings and model data stay on the machine.

## Start on Windows

Requirements: Python 3.11+, FFmpeg on PATH, and the pinned Godot runtime.

```powershell
py -3.11 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m pip install -r music_brain\requirements.txt
.venv\Scripts\python.exe tools\prepare_assets.py --skip-morphology
.venv\Scripts\python.exe music_brain\launch.py
```

You can also double-click [music_brain/START_MUSIC_BRAIN.cmd](music_brain/START_MUSIC_BRAIN.cmd). Choose an audio file, process it, then export the project as an MP4. The interface uses the detailed separated-instrument analysis and keeps timing controls in the same view.

For a direct 4K/60 export:

```powershell
.venv\Scripts\python.exe music_brain\export_video.py path\to\project.json output.mp4 --fps 60 --width 3840 --height 2160 --brain
```

## Development

```powershell
.venv\Scripts\python.exe -m pytest music_brain/tests -q
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_scene_geometry.gd --quit-after 10
```

Full generated recordings, audio files, neural binaries, Godot caches and rendered videos are excluded from the repository; only the lightweight preview above is included.

See [Music Studio documentation](music_brain/README.md), [architecture](music_brain/ARCHITECTURE.md), and [third-party attribution](THIRD_PARTY.md). Neural activity is a control signal from a simulation; this project does not claim biological validation.

