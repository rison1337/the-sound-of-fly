# EXC3_CM3: reference study

Status: **reference analysis and implementation specification**, not a claim that the running renderer achieves this design.

Reference: kkmfd, *EXC3_CM3*, local user-supplied dataset, approximately 72.28 seconds. The artist's video, photographs and frames are not application assets. This study extracts design relationships for original procedural imagery.

## Evidence inspected

- All 289 uniformly extracted frames, at 4 frames per second, across all 19 contact sheets.
- Six transition windows at 12 frames per second: around 23.323, 33.500, 35.168, 50.383, 56.189 and 62.129 seconds.
- Full-resolution frames around 26.25 and 57.50 seconds to inspect silhouettes, occlusion, material boundaries and perspective.
- The supplied PCM audio through the application's current `AudioAnalysis`, offline. This is numerical analysis, **not a claim of subjective listening** or a verification of every musical beat.
- Current `scene_history.gd`, `visual_events.gd`, `spatial_stage.gd` and transition shader.

Time ranges below are approximate, inferred from the extraction cadence. Small one- or two-frame inserts may be missed at 4 fps. Automated image-change detections are not ground-truth shot boundaries.

## What makes this different from the current visualizer

The reference composes **relationships**: a card opens into a spatial arrangement; a circle becomes a portal; linework becomes architecture; a previous composition reappears inside a screen; a material sequence stays inside a persistent silhouette. Many elements coexist, but they share boundaries, planes, axes, masks or a camera trajectory.

The current renderer mostly distributes reusable meshes in a layout and adds activity-driven motion and detail. Its topology labels promise much more variety than the actual primitive vocabulary and relationships provide. Raising event counts or deformation amplitude cannot close that gap.

The reference also operates on several timescales. A continuous world can last seconds while framing, inserts, materials and silhouettes change much faster. The current regular 1.15–2.65 second shot reset and similar reveal/decay envelope flatten those differences.

## Timeline observations

| Approximate time | Observed construction and motion | Reusable principle |
| --- | --- | --- |
| 0–19.75 s | A luminous violet spherical/horizon composition develops continuously. The central structure recedes, revealing surrounding space; aligned circles and a vertical stream become visible. | Build scale and depth over time. Continuous development can be active without repeated hard cuts. |
| 19.75–23.25 s | Edge-aligned type frames the established image; the luminous field is removed while the circular motif remains. Polarity changes precede the next composition. | Preserve an identifiable component while changing its context. Type has deliberate anchors. |
| 23.25–26.75 s | White poster fields, irregular opaque cutouts, photographic surfaces, small spheres and lines, sudden close-ups and chrome-like forms. Several compositions occupy only part of the frame. | Use cutouts and local material changes; vary occupied area and crop. Do not cover every exposed region with generic detail. |
| 26.75–29.5 s | Horizontal editorial strips, a large wire sphere, a brief dispersed symbol field, macro rounded objects, narrow architectural/photo cards. | Change the spatial organization and scale distribution. A dense burst is one operation among several. |
| 29.5–31 s | Strong violet perspective, stretched reflective surfaces and folded radial forms. Sparse label/text elements sometimes frame the surface. | Make a surface itself the environment. Distortion changes geometry and perspective, not just the overlay. |
| 31–34 s | Compact collages, a colored concentric motif, the motif embedded in a street image, reduction to a diagram, then construction of a flat audio/voice card. | Reuse a motif through new roles: object, image, schematic and transition anchor. |
| 34–40 s | A graphic card shrinks and tilts; its contents open into spatial planes and curved geometry. The view travels between elements, revealing new arrangements along the same structure. | Preserve object identity across 2D and 3D. Compose a path through a connected assembly. |
| 40–44.5 s | Fast contrast changes: blue editorial frames, dark fields, small image windows, physical-looking surfaces and nested editor/screen imagery. | Treat the frame as a viewport that can become an object in another frame. |
| 44.5–47.5 s | Image/material substitutions under an edge-letter motif, digital tearing, then thin diagrammatic linework that grows across a pale field. | A motif can hold the montage together; a change in mark density can reset attention. |
| 47.5–50.25 s | A hard split between a blue panel and repeated perspective imagery; vertical strips develop, then rounded forms and additional surfaces cross those partitions. | Spatial partitioning makes dense imagery readable. Overlap is deliberate and opaque where needed. |
| 50.25–52.25 s | A spherical/radial field surrounds a central aperture. The aperture's contents change rapidly while the outer construction remains recognizable. | Put fast material/content changes inside a stable moving mask. |
| 52.25–55.75 s | A dark orbital/diagrammatic structure develops into depth, interrupted by large typographic inserts and changes in polarity/perspective. | Alternate views of a coherent construction; not every visual change requires destroying the world. |
| 55.75–58.5 s | Lines converge in perspective, become dense extruded architectural elements, and fill the foreground. A large arc frames the flythrough as the view rolls. | Enforce a shared vanishing direction, strong near/far ratios and foreground occlusion. The camera passes through the construction. |
| 58.5–62 s | Wire space collapses into a framed violet interface-like world, which accumulates objects, windows and short typographic interventions. | Capture/reframe an existing world; build a new organization around its image. |
| 62–64.25 s | A large fixed word silhouette contains rapidly changing images/materials; corruption affects its edges and internal regions. | Separate silhouette persistence from material turnover. For this project, use a geometric mask most of the time instead of a word. |
| 64.25–70.5 s | A small window changes aspect ratio and content, then opens into a filmed display and credits. | Transitions can grow from the geometry of the preceding image. |
| 70.5–72.28 s | Fade/end. | An ending is not a runtime inactivity rule. |

## What the timing measurement does and does not establish

The dataset contains **85 threshold-detected image changes**. Across consecutive detections, the median gap is **316.5 ms**, with a 25th–75th percentile interval of approximately **191.7–567.2 ms**. There is a long continuous introduction, and a gap of approximately 4.7 seconds in the later detected sequence. These values describe the detector output, not a universal target shot duration.

In 22–64.5 seconds, the existing audio detector finds 293 merged transient timestamps. 84.1% of 82 detected image changes are within 75 ms of one of these timestamps. However, deliberately time-shifted controls still produce 79.3% proximity. This small separation means that **event density alone cannot demonstrate precise audiovisual synchronization**. It would be misleading to claim that all cuts have been verified as beat-matched.

The detector also finds 126 events during the 22-second introduction, when no threshold image cuts occur. Therefore: keep an immediate visible reaction to detected transients, but do not equate every transient with a full scene reset. It may articulate an existing object, change an internal view, or initiate a camera segment.

Reproduce the report from the repository root:

```powershell
.venv\Scripts\python.exe music_brain\tools\analyze_reference.py "PATH_TO_EXC3_CM3_dataset" --output music_brain\runtime\reference-analysis\timing.json
```

## Rules to implement

These are **proposals inferred from the reference**, not measured properties of the author's production process. The accompanying [reference grammar specification](reference_grammars.json) is a design input and is not yet loaded by the renderer.

### 1. Compose connected assemblies

Give major components stable neural ownership plus explicit relationships: `attached_to`, `surface_of`, `clipped_by`, `extruded_from`, `instance_of`, `frames` and `shares_vanishing_axis`.

Components need different scale distributions, occlusion roles and materials. Many objects may remain visible simultaneously. There is no global rule limiting the result to one hero and one support.

Examples:

- A planar contour from a neural-band trajectory is extruded into slabs; lines on its surface separate into ribs; the camera enters between them.
- A grouped neural motif is viewed first as a cutout, then as a macro detail, then as repeated fragments in a deep architectural space.
- A previous procedural scene is rendered inside a moving aperture while a new surrounding structure is assembled.

### 2. Separate world continuity from editorial changes

Retain an assembly across several framings. Use three overlapping timing layers:

- **Local articulation:** approximately 30–150 ms for a real spike trace, material edge, joint displacement or small insert.
- **Framing/montage:** approximately 100–700 ms for an abrupt camera crop, panel substitution, region inversion, material replacement or silhouette transformation.
- **World development:** approximately 1–8 seconds for an assembly to open, become architectural, change dimensionality or pass into another world. These are design starting ranges, not mandatory timers.

Use raw audio timestamps to schedule an already-defined operation. Neural history and source ensembles select its content and geometry. A strong transient must be visible promptly even if the world continues.

### 3. Make camera motion structural

Use authored *rules* for path segments, with neural parameters: front-on presentation, lateral passage between panels, near-surface macro, a depth plunge, an orbit break or a rolling flythrough. Projected component scale should change substantially during selected segments.

Current sine offsets of the same camera cannot substitute for entering a space. A wide shot, a clipped close-up and an interior should be different views of the same assembly when continuity is appropriate.

### 4. Transform forms instead of uniformly wobbling primitives

Derive silhouettes, subdivisions and folds from the 16-band neural trajectory and ensemble histories. Use per-source activation to open a joint, extend a slab, release a segment or shift a region. Preserve a recognizable contour long enough to see its change.

Do not apply the same scale pulse and sinusoidal displacement to every node. Variation must alter proportions, connectivity, depth and motion roles, not only choose a different random seed.

### 5. Use material contrast and masks

Favor intentional relationships between flat ink, pale substrate, dark voids, reflective forms and thin linework. Dense scenes can have large opaque masses and strong depth occlusion. Repeated transparent overlays flatten everything into the same visual layer.

Fast changes can occur inside a mask while the silhouette persists. A transition may turn the mask into an aperture or take the camera through it. Original procedural textures and rendered geometry substitute for the reference's photographs.

### 6. Keep text rare, according to the user's preference

The reference has both text-free sections and emphatic typographic passages. The user explicitly prefers less dominant text, so do not copy its typography density. Preserve the existing approximate 50–60% text-free, 25–35% small/medium, 10–15% typography-heavy target, and let geometric silhouettes perform most mask/montage roles.

Text, when present, must belong to a panel, margin, curve or physical surface. It must not fill empty areas by default.

### 7. Reinterpret recurring motifs

The reference repeats circles, violet/blue accents, diagrams, editorial framing and previous imagery. Novelty is often a **change of role and context**, not total replacement of every motif.

Track motif + scale + framing + material + connectivity + depth. Reusing a motif as a portal after it appeared as a surface is meaningful variation. Cycling through all 14 topology names under unchanged input is not sufficient evidence of musical specificity.

### 8. Preserve the neural and latency constraints

- Fixed model weights; all memory here is bounded visual/audio history.
- All 165,122 cell states and all 256 ensembles continue through the current binary path.
- Individual spike events retain real cell identity; do not replace them with decorative uniform dust.
- No raw spectral amplitude path into object geometry. Raw audio remains the timing source; neural response supplies content and motion parameters.
- Pool assemblies, render targets, geometry buffers and event storage. Compile/warm material variants before the performance sequence.
- Diagnostics and media analysis must not block the display thread.

## Specific implementation gaps found

| Current code | Consequence | Required architectural change |
| --- | --- | --- |
| `spatial_stage.gd` constructs six generic meshes and positions them separately | Many named spaces still look like arrangements of the same basic objects | Build related procedural surfaces, cutouts, ribs and panel assemblies with shared contours |
| `scene_history.gd` heavily penalizes recent topology labels | A preset-like rotation can masquerade as novelty | Compare visual structure and transformations; allow contextual return of a motif |
| `visual_events.gd::_cut()` retires every event | No graphical inheritance between worlds | Carry selected components or a rendered view across a transition |
| The shared transition shader hides the whole stage at the start; per-object reveal also starts near zero | Frequent empty/weak birth frames, softened impact | Distinguish hard replacement, object-local construction and content-preserving transitions |
| Camera regimes mostly use modest sine offsets around one viewing position | Weak spatial transformation despite real 3D | Camera segments tied to the assembly and its development |
| Similar sinusoidal and scale response is added to most objects | Motion reads as generic wobble | Assign neural events different structural actions and motion roles |
| QA captures 41 frames and writes PNGs synchronously after capture | Only four seconds of evidence; export may cause a visible stall | Ten-second capture, actual timestamps, background export and a contact sheet with shot/motif/operation metadata |

## Acceptance evidence for the next implementation

Capture 10 seconds of real loopback-driven playback at 100 ms intervals. Include the song-relative time, world ID, framing ID, motif identity, transition operation, neural state age and actual capture timestamp. Save frames asynchronously and leave the application in normal mode afterwards.

Inspect a contact sheet and selected sequences for:

1. At least one clear planar-to-spatial transformation with recognizable shared components.
2. A real interior/macro/flythrough change of scale, not just a rotating object against the same background.
3. Persistent motifs transformed across views, alongside clearly distinct constructions.
4. Fast local changes, short editorial changes and longer development, with visibly different pacing.
5. Text-free compositions that are complete through geometry and material design.
6. Dense sections with coherent silhouettes, masks and occlusion; no permanent full-screen detail wallpaper.
7. Prompt transient articulation without resetting every world, plus substantial motion driven by the neural response.
8. No mandatory fade-to-empty at every shot birth and no capture/export stall.

Compare two distinct audio passages, including passages with similar onset rates but different neural-band histories. A high average pixel-difference score alone does not establish musical specificity, coherent design or novelty. Low latency alone does not establish any of those either.
