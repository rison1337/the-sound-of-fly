# Phrase development and closed geometry

## Changes

- Per-phrase construction plans use scored attack times, downstream event samples,
  sustained voice memory and the existing neural trajectory. No model learning.
- Groups build, articulate and close together; tunnel cameras include bounded
  lateral movement with less continuous forward travel.
- Neural context sets panel proportions and two/three-column arrangements.
- Fixed `scale * rotation` shear in the parent/child graph. Closed ribbons have
  physical rims and periodic neural sampling; rounded sculptures have pole normals.
- Removed floating box details from orbital/sculptural scenes and faint circle
  overlays from panel materials. Aperture levels have independent pivots.
- Maximum-response geometry checks caught and corrected crossings in partitions,
  folded relief, tunnel corners and late-phase orbital levels.

## Validation

`test_phrase_design.gd`: cue alignment, changed timing with fixed response,
silent downstream response, sustained bass without attacks, continuous nonsingular
poses, and a circular child under a rotated anisotropically sized parent.

`test_scene_geometry.gd`: all twelve grammars, seven stages at maximum plan
amplitude/depth, conservative root envelopes, graph ownership, no floating boxes
in the affected grammars. These bounds do not prove every possible shader pose.

GPU `test_surface_render.gd`: foreground occlusion, intact panel under stress,
closed frame/ribbon joins, edge-on ribbon thickness, categorical-role stability,
and valid normals across closed morphologies. Run with a GPU renderer, without
`--headless`, because the test waits for rendered frames.

Also passed: event pool, scene history, voice and shot-language regressions.
Python suite: 27 tests passed before the final GDScript-only adjustments.

## Visual review

Version 2 was inspected across the track, and in 100 ms sequences covering
6–16 s and 97–101 s. Floating boxes are absent in orbital scenes. These sequences
show continuous object changes and print/spatial cuts; panel and ring motifs are
still recognizable. Frame difference is not an aesthetic or synchronization score.

Final validation artifacts are under `runtime/offline-qa/phrase-design-v3`.
The renderer preserves all 165122 recorded cell states and the 256 ensembles.

## Surface clarity pass (v8)

- Removed the per-surface registration-stroke layer. It was a decorative event
  texture, so it could not improve neural timing and appeared as flickering dashes.
- Quiet paper surfaces use a mid-tone material separate from the paper backdrop;
  this keeps panels, rings and tunnel inserts readable in both polarities.
- GPU surface QA now checks foreground occlusion, neural deformation after the
  mark layer is removed, and a minimum luminance contrast of 0.14 across four
  palettes, two polarities, panels and torus rings. The measured minimum was
  0.391. The test suite reported zero failures.
- Full v8 export: 8879 frames at 1920x1080/60fps, audio muxed and frame-count
  validated. A 50 ms review sequence from 74.5�76.5 s contains no surface
  scratch flicker.

## Final surface tone adjustment

The first contrast pass used a mid-grey fill and was too heavy. The final material
uses a near-white tone (`mix(ink, paper, 0.92)`) with only enough separation from
the backdrop to keep silhouettes visible. The GPU minimum measured luminance
separation is 0.0585 across all palette/polarity and panel/ring combinations.

## Line cleanup and articulation (v11)

- Removed detached line children from panel assemblies and the full-width
  underline from the bar motif. Graphic contours use an accent-tinted dark color;
  wave, rosette, scan and rib motifs have fewer, narrower stripes.
- Restored impact as a shared structural pulse across musical roles. Panels have
  stronger depth contact, compression and pitch/sway; the camera edit pulse has
  a larger bounded field-of-view response. Voice timing and source data remain
  unchanged.
- GPU surface, geometry and phrase-design checks passed. Minimum measured surface
  contrast remains 0.05854; normal-scale image difference is 0.00003957.
  Python suite: 27 passed.
- Exported 8879 frames at 1920x1080, 60 fps with the track audio to
  runtime/offline-qa/phrase-design-v11/music-studio-clean-v11.mp4.
  Inspected frames at 47, 75.5, 96, 105 and 129 seconds and a 40-frame sequence
  from 74.5 seconds at 50 ms intervals. The sampled sequence has no detached
  registration marks. This visual sampling does not prove artifact-free rendering
  at every frame or establish subjective audiovisual synchronization quality.

## Studio interface and 4K export (v12)

- Replaced the legacy Tk control surface with a compact dark CustomTkinter studio
  layout. Preview and Sync diagnostics are removed from the main workflow; the
  user now processes a track, opens a processed project, and exports the MP4.
- 4K UHD (3840 x 2160) is the default export choice, with 720p, 1080p and 1440p
  still available. Export uses the requested native viewport size; a 30-frame
  3840x2160 smoke render with audio and the compact brain overlay passed.
- Typography is disabled in the artwork path and scene-name metadata is hidden
  from the visual canvas. The optional brain overlay hides its labels and follows
  an absolute soundtrack-time camera orbit in a small rounded card at top right.
  This keeps the composition visible while retaining neural context.

## Brain overlay framing (v13)

The compact export brain keeps its card size and now uses a closer camera distance
(multiplier 0.56 instead of 0.92). This makes the neural silhouette readable while
leaving the visual composition unobstructed. A 3840x2160 smoke export passed after
this change.

## Studio workflow simplification (v14)

- Removed the analysis dropdown from the studio window. Processing always uses
  the detailed Demucs path; the interface retains only start and length timing.
- Renamed the export toggle to `Brain overlay` and removed the compact qualifier.
