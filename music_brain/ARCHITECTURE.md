# Offline Music Studio architecture

## Pipeline

`file -> FFmpeg PCM -> optional Demucs stems -> future-aware musical score -> fixed fly model -> indexed full-state recording -> Godot -> preview / FFmpeg MP4`

The UI is `studio.py`. Processing (`prepare.py`) and export (`export_video.py`) are owned subprocess jobs. Cancelling targets only the current job tree. No loopback capture service is started. `launch.py` is a compatibility entry point and `START_MUSIC_BRAIN.cmd` opens the studio directly.

## Audio and timing

`score.py` decodes stereo 24 kHz PCM, retaining stereo power rather than summing phase-opposed channels. A centred 2048-sample STFT has a 240-sample (10 ms) hop. Future-aware temporal/frequency median filters provide a harmonic/percussive fallback. Detailed analysis uses an isolated Demucs environment and fixed htdemucs weights. Stems are resampled back to the exact input sample count.

Six overlapping roles carry independent envelopes: impact, bass, mid attack, high percussion, melodic and sustained. Pitch is a spectral contour, not a polyphonic transcription. Event peaks retain role, timestamp and confidence. A short RMS refinement estimates attack timing; it is an estimate, not guaranteed sample-perfect instrument isolation. No beat-grid quantization moves original attacks. Tempo is reported only with confidence.

Phrase boundaries compare past and future spectral histories. They allow up to 650 ms of preparation. Audio chooses event time and sensory stimulation. Geometry, colour and deformation receive neural readouts, not raw role amplitudes.

## Fixed brain and storage

The existing MaleCNS simulation uses 165,122 neurons with fixed connectivity and weights. Disjoint engineered sensory assignments receive the six roles, with a moving pitch excitation across 16 bins. They are not biological instrument categories. `downstream.py` follows the CSR's real pre-to-post orientation and selects 384 cells per voice by two/three-edge path support and role selectivity. All potentially stimulated cells are excluded at every routing hop and from final readouts; the six readout sets are also disjoint. Absolute weights select topology; original signed weights still drive the simulator. A selected cell may also have a shorter direct postsynaptic connection.

`calibration.py` sends three fixed probes per voice and measures downstream onset, peak and release. Only responsive non-input cells are retained. `neural_audio.py` derives the six voice rates, spike rates, contour and responding fraction ONLY from these calibrated downstream sets. Per-voice lookaheads cause a real downstream peak to arrive near its source attack. Sparse downstream rates use the measured fixed transfer scales, with no audio or sensory-rate blend. Runtime assertions reject any overlap with `driven_mask`. `readout_routes.json`, `calibration.json`, `voice_timing.json` and `sync_report.json` record exact identities and timing. Existing 16 sensory-band summaries remain explicitly sensory summaries for scene-history context; they are separate from these six downstream voices. All original 256 ensemble measurements and full population frames remain present.

Simulation runs in 2 ms steps, independent of rendering speed. `prepare.py` records every 20 ms (50 Hz). Each role uses its own calibrated peak delay for future-input stimulation; simulation starts before audible time zero. The renderer samples actual downstream responses in a bounded event window and aligns their articulation envelope with the source attack, retaining the response strength. No audio amplitude is substituted for a silent readout. All state is simulated, not measured from a living fly.

Each `neural.bin` record has two little-endian uint32 lengths, a UTF-8 JSON header and a DEFLATE payload. `index.json` holds exact audio times and file offsets. The payload remains 512 x ceil(N/512) RGBA8:

- RG: uint16 firing rate in 1/32 Hz units;
- B: spikes since the previous recorded frame;
- A: latest spike age in 2 ms steps, 255 = old/absent.

`project.json` is committed last, so cancelled partial recordings are not offered as completed projects. Cache identity includes source bytes, start/length, analysis mode and computation source files. Full states are read incrementally rather than expanded for an entire song in RAM.

## Visual development

The existing 512-slot event pool, 320-part transform graph, 256 ensembles and GPU population renderer remain active. Six persistent voices supplement this detail. `neural_voices.gd` holds fixed-size arrays and a 6 x 2 float texture. Different envelopes produce rebound, sustain, slice, notch and contour movement; source ensembles remain explicit.

Composition advances on a fixed 120 Hz clock. Individual audio attacks are delivered once, without accumulating a render queue. High-percussion events articulate local details rather than cutting the entire world. Future phrase boundaries prepare a camera move and may request a world transition. A bounded 24-entry memory compares neural phrase shapes, retaining motifs in different visual roles. This memory is renderer state, not learning in the fly.

`scene_history.gd` preserves four seconds of 16 neural-band trajectories, ensemble bursts, population centroid, short/medium/track memory and recent composition history. `score.py` also creates phrase intervals with buildup/fill/silence labels. Scene duration is the current phrase remainder; a new phrase requests the cut, while typed attacks continue to articulate the existing construction. These build structural descriptors rather than a scalar random seed. Coactivity and propagation are population proxies, not causal tracing of synapses.

Spatial grammars include folded relief, architecture, radial chambers, panel tunnels, cutout collage, macro ribbons, nested screens and neural volumes. Parts have actual parent-relative transforms. Reserved local envelopes limit solid crossings. Shared opaque print materials permit 2D-to-3D transformations; local masks and slice displacement alter existing geometry. Temporal GPU history appears only inside bounded apertures. Neural voice deformation and individual spike displacement remain bounded inside reserved local domains.

`shot_language.gd` adds an editorial timescale within each phrase. Typed attacks request an edit; downstream levels, contours, changes and coactivity choose presentation, crop and framing. A minimum hold and recent-view penalties prevent repeated edits; there is no time-only carousel. Camera position, target and roll move continuously within a world. The five editorial states map to complete spatial or complete print views. `editorial_mask.gdshaderinc` no longer applies persistent cards, apertures or strips over the spatial image. A view switch takes effect on the scored attack, without a delayed boundary crossing foreground geometry.

Panels use preallocated closed-shell meshes with front, back and rim faces. Nested frames have an annular domain; cutout contours deform the domain instead of discarding pixels. No shader clamps vertex positions or discards musical slits through a panel. Smooth profile interpolation preserves continuous normals; small spike displacements taper before panel boundaries. Coplanar outline meshes are not emitted.

The 512-slot event pool still owns source, birth, lifetime and strength. A bounded 256-owner field selects a living mark per surface; the spatial material renders this mark inside its UV domain with the same depth as the surface. Marks cannot pass through occluding geometry. The canvas event renderer is limited to typography/data annotations in full print views. This replaces screen-space rings/crosses projected onto arbitrary foreground objects.

Printed material (role 4) and past-world screen (role 5) are explicit; ink, paper and accent planes retain their material role. Screen content is not placed on every printed object. Closed parametric domains use continuous trajectory coordinates and vanish their local displacement at the seams and poles. Four-sample MSAA handles geometry silhouettes; phase derivatives filter procedural ribs before their sine is evaluated. Actual local spike deformation remains depth-tested by the surface geometry. The optional floating 2D spike field is disabled by default because it has no access to the 3D depth buffer; the complete population texture, 256 ensembles and brain panel remain active.

Instance identity and ensemble response use flat shader interpolation. Musical-role IDs must never be perspective-interpolated: rounding around an integer before `floor()` can make adjacent fragments select different voices, producing stippled material artifacts. The GPU surface regression compares exact-integer and slightly offset identities under perspective. Closed sculptural domains use a smaller deformation envelope than sheets; the print language keeps larger continuous voice-specific motion. Captured historical content contributes only a bounded echo inside its designated screen.

Parts also articulate in their local frames. Tonal sheets have bounded pitch/yaw and slight contraction, sculptural domains turn with the continuous downstream phase, arcs rotate in their own plane, and percussive details contract and recover on scored contacts. Parent actions propagate through the assembly graph. Phase does not advance without downstream activity; audio amplitude is not used as a fallback movement signal.

The optional `--qa-sequence=ABSOLUTE_PATH` captures 101 frames targeted at 100 ms intervals over soundtrack seconds 6–16. PNG/contact-sheet encoding runs on a worker. Metadata records actual audio times, intended times, world, view and presentation IDs; capture overhead is observable rather than hidden by pausing the sampling clock. `--qa-art-only` hides controls and the brain panel for design review. Frame-exact export is the appropriate artifact for checking exact cadence.

## Playback and export

### Phrase construction plans

`recording.gd` caches `phrase_design.gd` scores when opening a project. Ordered
cue windows select nearby attacks with a genuine downstream response. Missing
responses keep neutral stage timing; there is no audio-amplitude substitute.
The current four-second neural trajectory and sustained six-voice memory select
motion axes, stagger, depth and panel proportions at the phrase boundary. Plans
are held for the phrase. Stages smoothly assemble, unfold and close the existing
parts while individual voices continue their local articulation.

Parent actions are applied before anisotropic domain sizing. This prevents a
thin panel from shearing a circular child when rotating. Annular ribbons now
have thickness and periodic profile sampling across the join; spherical poles
use analytic normals. The centre of an aperture and its orbital levels have
independent pivots along a shared axis. Floating small box meshes are suppressed
in orbital, aperture, cutout and sculptural grammars. Their percussive readouts
still articulate surfaces. Phrase geometry regression exercises seven phases
of all twelve grammars at maximum plan strength, rather than only static poses.

Godot loads the decoded soundtrack and uses the audio playback clock, corrected for reported output latency. Startup prepares the first construction before playing audio. Space pauses playback; Restart reloads the project. Preview does not rerun the neural simulation.

For export, playback time is `frame_index / FPS`. Godot renders every frame and sends RGB24 bytes to a localhost encoder socket. Python accepts exactly one frame, writes it to FFmpeg stdin and acknowledges it; backpressure bounds memory. FFmpeg adds the original soundtrack. There are no accumulated PNG frames. The target MP4 is replaced only on success. A locked existing target causes publication under a fresh sibling name; a validated movie is retained even if publication fails. Export speed is independent of soundtrack timing.

## Limits

Demucs can leak or misattribute instruments. Pitch/phrase analysis is approximate. Rendering cannot infer semantic intent as an authored music video does. Preview frame pacing depends on hardware; offline export waits instead of dropping frames. Fixed-step composition aligns the score, but camera smoothing and GPU history are presentation operations, so preview at another display rate is not promised to be pixel-identical to export. State-file timestamps are not claims of measured audio-to-photon latency.
