# Droffel / Music Studio

**Choose music. Simulate a fixed fly brain. Preview and export audiovisual motion design.**

Music Studio is a file-based application inside Droffel. It uses all **165,122 simulated neural states**, 256 anatomical ensembles, and six synthetic sensory channels to animate connected 2D/3D constructions. The fly model does not learn or change synaptic weights. The renderer retains short-term and track-level composition history.

## Start

Double-click **`START_MUSIC_BRAIN.cmd`**.

1. **Choose audio** — WAV, MP3, FLAC, OGG, M4A and formats decoded by FFmpeg. Set start/length to work on an excerpt; length `0` processes the full track.
2. **Process music** — analyse the whole excerpt, separate musical roles, then record the complete neural response. Completed projects are cached locally.
3. **Preview** — play the original audio with the recorded response. Space pauses both; Restart starts again; B expands the brain panel; Tab hides controls; F11 toggles fullscreen. D opens the per-role sync traces; Settings can audition separated stems and store a preview output offset.
4. **Export MP4 with audio** — select 720p, 1080p, 1440p or 4K at 30/60 FPS. The brain panel is optional; interface controls are omitted. Offline rendering waits for every frame instead of dropping frames.

There is **no system-audio/live capture** in this version. Only explicitly chosen files are processed. Decoded audio, separated stems, score and compressed neural recordings are stored under `runtime/projects/`; they are not uploaded. The source file is unchanged.

## Analysis modes

**Detailed / separated instruments** uses the fixed pretrained [Demucs htdemucs model](https://github.com/facebookresearch/demucs) for drums, bass, vocals and other accompaniment. Frequency regions and temporal structure of those stems form six overlapping roles: impact, bass, snare-like attack, high percussion, melodic voice and sustained bed. This is approximate source separation, not perfect instrument recognition or note transcription.

**Fast / harmonic-percussive analysis** uses centred spectral median filters without a separator model. It is useful for quick drafts and synthetic material. A bright synth can overlap the percussion role; a low attack can overlap bass. Neither mode claims biological auditory tuning.

The detailed mode uses a separate Python environment so PyTorch does not change Droffel's simulation dependencies. If it is missing, run `SETUP_SEPARATOR.cmd`. The initial setup downloads PyTorch/CUDA packages (several GB); the first detailed analysis downloads an approximately 80 MB model. After installation/model caching, processing is local. FFmpeg must be on PATH.

## What drives the picture

- Typed sample-clock attacks schedule local articulation. Predicted phrase boundaries allow camera preparation and transitions before the boundary.
- Audio envelopes and pitch contours stimulate disjoint synthetic input populations of the fixed brain. Each of the six visual voices starts with up to **384 downstream candidates**, selected by actual directed two/three-edge paths; calibration retains the responsive subset. Exact cell counts and identities are saved in the project. All directly stimulated cells are excluded. Some selected cells also have a shorter one-edge path; two/three-edge support is not a claim of minimum graph distance. The simulation retains signed synapses; absolute weights are used only to select paths.
- An impact compresses and rebounds; bass bends a mass; an attack shears a surface; high percussion opens local notches; a melodic response changes a continuous contour; a sustained response holds structures.
- Individual spikes remain local micro-events. Complete population state and 256 ensembles still reach the renderer; the six voices supplement them.
- Returning neural phrase shapes retain motif identity but return with a different framing. Existing surfaces can unfold from flat print into space, open an aperture onto a previous construction, or become a tunnel.

The renderer combines opaque print design, closed panel shells, cropped materials, physical geometry and bounded deformation. Text is a rare accent. This is procedural motion design informed by a fixed neural simulation; it is not a reconstruction of a reference artist's authored edit.

Inside a musical phrase, downstream population changes select full spatial views and full-frame prints. Each view owns the whole frame: persistent screen masks no longer slice through foreground objects. Camera moves develop the construction; print/space cuts land on scored attacks. Close-ups and depth passages reframe the same construction. Rounded extrusions, folded shells, toroidal forms and lobed surfaces use the neural history for their proportions. A scored onset can change the framing; elapsed time alone does not cycle views.

Panels have front, back and side faces; holes are actual geometry. Local event marks are ink in the owning surface material, so foreground geometry correctly hides them. Flat overlays are limited to small print annotations. Surfaces have separate ink, paper, accent, reflective and printed roles. Past-world images are restricted to designated screens. Procedural ribs filter out detail that is smaller than a pixel, and the 3D viewport uses 4× multisampling. Cell-driven local deformation stays active on real surfaces; the optional **Floating spike traces** preview overlay is off by default because it does not share the 3D depth buffer.

## Files and reproducibility

`phrase_design.gd` compiles a construction plan once per phrase. Scored attacks
set ordered development cues; downstream attack samples and sustained neural
voice memory set the motion, depth and panel proportions. Attached parts move
together through build, unfolding and closure. Continuous bass is retained even
when no new bass attack is detected. Rings have closed front/back/rim geometry;
small floating box details are omitted from orbital and sculpture constructions.

`project.json` is written only after simulation completes. `neural.bin` contains compressed full-population frames at 50 Hz; `index.json` indexes them. `score.json` contains unquantized attacks and future phrase boundaries. Preview and export integrate composition at a fixed 120 Hz and use the same recording. Each voice uses its measured downstream peak delay as a per-role lookahead. The source attack remains the visual contact time; this is a documented stimulation pre-roll, not fabricated spikes.

Projects can be reopened using **Open processed project**. Cancelling a job leaves completed projects intact. Export writes to a temporary MP4 and replaces the chosen target only after successful encoding. If a player locks an existing video, the completed export is saved next to it with a new name, shown in the status bar. Cache size depends on duration and neural activity; rendering streams frames directly to FFmpeg without storing a PNG sequence.

`readout_routes.json` records the exact input/readout identities and path-selection metadata. A fixed three-pulse probe measures onset, peak and release per downstream voice and writes `calibration.json`; the resulting per-role lookaheads are recorded in `voice_timing.json`; `sync_report.json` compares every role attack with its recorded downstream response. Runtime assertions enforce `readout_cells ∩ driven_mask == 0`. Projects made with the previous sensory readout must be reprocessed. The optional full-model diagnostic `tests/check_downstream_model.py` compares identical stimulation with intact vs disconnected propagation; the disconnected network exists only inside that test process.

## Development

From the Droffel root:

```powershell
.venv\Scripts\python.exe -m pytest music_brain/tests -q
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_voices.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_events.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_scene_history.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_scene_geometry.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_phrase_design.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path music_brain/app --script res://scripts/test_shot_language.gd --quit-after 10
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path music_brain/app --script res://scripts/test_render_masks.gd
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path music_brain/app --script res://scripts/test_surface_render.gd
```

CLI processing and export:

```powershell
.venv\Scripts\python.exe music_brain/prepare.py track.flac --start 30 --duration 20
.venv\Scripts\python.exe music_brain/export_video.py path/to/project.json output.mp4 --fps 60 --width 1920 --height 1080
.venv\Scripts\python.exe music_brain/tools/review_video.py output.mp4 runtime/review --start 6 --duration 10 --fps 10
```

See [architecture](ARCHITECTURE.md) and [reference study](docs/REFERENCE_EXC3_CM3.md). The original terrarium and Isaac controller are separate applications.
