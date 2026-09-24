# Editorial and geometry review — 2026-09-23

## Scope

The existing fixed-brain recording is unchanged. This revision changes presentation, geometry, framing and opaque composition inside a phrase. It does not introduce learning or substitute raw audio amplitude for downstream neural response.

- Neural-volume layouts use different near/far scales instead of an orb grid.
- Rounded extrusions, toroidal forms, folded shells and lobed surfaces derive proportions from the held neural descriptor.
- Downstream population balance chooses framing and presentation on scored attacks; time alone cannot cycle presentations.
- The print, spatial image and attached micro-events share an opaque mask. Hidden spatial detail does not bleed through paper.
- Graphic layouts use unequal regions and enlarged crops. Split/aperture views do not add a second tiled grid.
- A persistent construction can alternate between full spatial views, prints, partitions, apertures and strips without resetting the brain or world history.

## Validation

Local project: `63a0b475f24e0d2d536a`, approximately 99.17 seconds, separated-instrument analysis.

- 26 Python tests passed.
- Six Godot scripts passed: neural voices, visual events, scene history, reserved geometry, binary decoder and editorial selection.
- The new editorial test checks time-only stability, silent-readout rejection, minimum hold, population-dependent framing and unchanged neural ownership.
- Actual OpenGL rendering and full MP4 export completed without engine errors.
- Final video: 1920 × 1080, 60 FPS, **5,951 frames**, H.264 with AAC audio. The encoder now checks the frame count before replacing the destination. Video covers the final partial audio frame; its tail is approximately 10 ms longer than audio.
- The first exported frame was visually inspected. Two initial viewport warm-up draws prevent an empty opening frame without advancing score time.

Review artifacts (local, generated):

- `runtime/offline-qa/music-studio-preview.mp4`
- `runtime/offline-qa/final-overview/contact.png`: one frame per second over 99 seconds.
- `runtime/offline-qa/final-100ms/contact.png`: 100 consecutive samples, 6.0–15.9 seconds.
- `runtime/offline-qa/editorial-v3/sequence.json`: preview sampling and scene metadata before the final macro-camera adjustment.

That preview sequence contains two phrase worlds and 17 view revisions across ten seconds. Its median sample lateness is 3.33 ms, 95th percentile 5.67 ms and maximum 63.88 ms. These numbers measure screenshot scheduling, **not audio-to-photon latency**. Final video samples are extracted every six encoded frames, exactly 100 ms at 60 FPS.

For the exported 100 ms sequence, the 10th/50th/90th percentiles of mean absolute RGB frame change are 0.0236 / 0.0538 / 0.2889. This describes motion and cuts; it does not establish beauty or perfect musical synchronization.

## Visual assessment and remaining limits

The full contact sheet shows changes between spatial architecture, radial structures, macro surfaces, panel tunnels and flat prints. Paper boundaries separate simultaneous imagery; close-ups preserve visible silhouettes after correcting an over-close camera.

Recurring optical motifs and some spatial arrangements remain recognizable. This is closer in composition and editing mechanics to the supplied reference, but does not match the variety or authored detail of that artist's video. The six-channel role analysis and phrase boundaries remain approximate. These aesthetic limits are not resolved by passing tests or by a high frame-difference score.

## Follow-up: surface clarity and continuous transitions

The follow-up replaces feathered side partitions with antialiased signed-distance masks and rounded paper cards/apertures. All four rendering layers use the same mask. Opposing card/aperture transitions pass through the spatial view to avoid a mid-transition grey veil. Camera position and roll interpolate between editorial views without switching projection halfway through a phrase.

Plain paper, ink, accent and reflective surfaces now retain their materials. Only designated print surfaces receive graphic patterns; only designated historical screens receive previous-scene imagery. Closed surfaces have continuous trajectory sampling and seam-safe local deformation. Denser meshes, 4x MSAA and derivative-filtered graphic ribs improve edge quality. Floating screen-space spike traces default to off and remain available in Settings; local spike-driven surface deformation and the full neural recording remain active.

Validation for this follow-up:

- Main script parsing, event behavior, reserved geometry and editorial selection checks passed.
- The new GPU mask test rendered all 25 presentation pairs at five transition positions: **125 states**, with no failures. It checks opaque endpoints, antialiased edge coverage and strip orientation.
- The full track exported through OpenGL without engine errors: **1920 x 1080, 60 FPS, 5,951 frames**. Video duration is 99.183008 seconds; audio is 99.173000 seconds.
- Reviewed the full-track one-second contact sheet, a ten-second sequence sampled every 100 ms, and full-resolution surface/architecture frames. The 100 ms RGB-change percentiles (10/50/90) are 0.01873 / 0.05743 / 0.28429; these are motion statistics, not an aesthetic or synchronization score.
- Audio analysis, neural simulation, voice calibration and recorded musical timing were not regenerated or changed.

Current generated artifacts:

- `runtime/offline-qa/surface-quality-final/music-studio-clean.mp4`
- `runtime/offline-qa/surface-quality-final/overview/contact.png`
- `runtime/offline-qa/surface-quality-final/100ms/contact.png`
- `runtime/offline-qa/surface-quality-final/detail.png`
- `runtime/offline-qa/surface-quality-final/architecture.png`

Opaque cards deliberately occlude the spatial image behind them. Reserved geometry checks cover independent root envelopes, not every possible child-surface overlap or camera occlusion. The review does not establish that every composition is collision-free or matches the reference artist's authored variety.


## Follow-up: depth-safe surface pass

The final surface pass removes screen-space marks from spatial views. Panels now use closed meshes with front/back/rim geometry, continuous profile deformation and no vertex clamp. Coplanar outline meshes are suppressed; local event marks are written by the owning depth-tested material. Full-frame print views and full spatial views no longer use a persistent card/aperture mask that can leave fragments at the edge.

The real GPU regression `test_surface_render.gd` passed: an event is visible on an exposed panel, hidden behind a foreground box, and a strong transient does not punch a hole through the panel. Existing event, scene, shot-language, geometry and editorial-mask tests also passed.

Full-resolution inspection then found an azimuth seam in nested frames. Fractional powers of `sin(2*pi)` amplified a tiny floating-point residue into a visible wedge. Radial superellipse/superellipsoid normalization now closes that seam without flattening vertices. The GPU regression also verifies a transparent frame opening and opaque coverage on both sides of its closed seam. Macro cameras were moved away from near-surface intersections after a first-pass frame at 30 seconds became almost empty; the corrected pass keeps the construction visible there.

The current selected project is the user's 147.968-second track (`036fecc32a7ffdf9c936`). The final export is `runtime/offline-qa/solid-surfaces-final/music-studio-solid.mp4`: 1920 x 1080, 60 FPS, 8,879 video frames, 147.983333 seconds of video and 147.968 seconds of audio. No neural recording or audio analysis was regenerated.

Review artifacts are in `runtime/offline-qa/solid-surfaces-final/overview/contact.png`, `100ms/contact.png`, and the full-resolution sampled frames. The 100 ms RGB-change percentiles (10/50/90) are 0.01048 / 0.03517 / 0.19691; this describes movement, not an aesthetic or synchronization guarantee.

## Follow-up: material identity and local motion

The user's 75 s / 99 s screenshots exposed a reproducible fragment-shader bug. Perspective interpolation of `INSTANCE_CUSTOM` let an exact integer musical-role ID drift slightly below its integer boundary. `floor()` then selected a different voice in neighbouring pixels, making printed surfaces appear densely stippled. Disabling cell bumps, memory and fold did not remove the artifact. Flat interpolation of instance identity and per-instance ensemble response removed it. A GPU regression compares the same perspective panel with role 1.0 and 1.001: mean RGB difference was 0.015421 before the fix and 0.00000665 after it.

Closed sculptures now use lower deformation amplitudes and a normalized five-tap spatial filter of their neural curvature profile. Squaring the seam envelope uses multiplication, avoiding undefined negative-base `pow()` during finite-difference normal calculation. The GPU test also checks filled interiors of all four closed morphologies for invalid dark normal pixels. Paper material has restrained shading, and paper/printed panels omit redundant attached bars. Past-world imagery contributes a bounded echo only inside designated screens.

Motion is more local: sheets hinge, sculptural objects turn with their downstream phase, arcs rotate and percussive details contract on contact. The print material uses stronger smooth voice-specific bending and broader, derivative-filtered ribs. No analysis, neural recording, downstream calibration or musical attack times were changed.

Validation:

- All 27 Python tests passed, including a new Windows locked-output publication regression.
- Godot event, voice, history, shot-language, geometry, mask and GPU surface checks passed. The final full export contains no engine/shader errors.
- `runtime/offline-qa/surface-followup/music-studio-refined.mp4`: 1920 x 1080, 60 FPS, 8,879 frames, 147.983333 s video / 147.968 s audio.
- Reviewed 74 full-track overview samples, 100 consecutive samples at 100 ms over 6.0–15.9 s, and full-resolution frames including 75, 99.4, 104, 115 and 118 s. The 100 ms change percentiles are 0.012337 / 0.032793 / 0.167286. These statistics describe change, not perceptual synchronization or design quality.
- Controlled before/after diagnostic images are in `surface-followup/probe/` and `probe-fixed/`; final review sheets are in `surface-followup/overview/` and `100ms/`.

The former output was open in a player and Windows prevented replacement. Export now publishes to a fresh sibling filename in that case and reports the actual path; a validated render is retained if publication otherwise fails. The final reviewed artifact above uses a separate explicit filename. Visual review covers the sampled scenes, not a proof that every possible generated camera view is free of occlusion. Composition families remain recognizable across the track.
