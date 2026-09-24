# Droffel / Isaac

A local Isaac controller connected to the MaleCNS neural simulation, with a
room map and live 3D brain activity. The Isaac dashboard and brain viewer use
English. The original terrarium keeps its Russian interface.

## Run

This launcher expects the existing Droffel setup: Python dependencies in
`.venv`, Godot in `.tools/godot`, and the prepared neural and visualization data.
Those generated files and tools are excluded from Git. See [README_RU.md](README_RU.md)
for the underlying local setup and model details.

1. Copy `game_paths.example.json` to `game_paths.json` and set your game folder.
2. Run **START_ISAAC.cmd**. It installs the Droffel mod and opens the service,
   observer and Isaac with `--luadebug` for LuaSocket.
3. Open a solo run with **Droffel Fly Brain** enabled in the game's mod menu.
4. Press **F6** to enable the controller. **F7** or **Esc** stops it.

If Isaac was already open when the mod was updated, close the game normally and
launch it again through START_ISAAC.cmd. Lua changes take effect after a restart.
The local integration was tested with Repentance+; Rebirth-only support is not
established by the game folder's name.

## Observe

- The dashboard shows the room, enemies and health in full-heart units.
- **Brain activity** opens the neural viewer. Drag to rotate, scroll to zoom.
- **Space** applies a scare stimulus. In the Isaac brain window, **P** stops control.
- The viewer has focus presets, cell-group filters, neural branches and sensory probes.
- Closing the brain window hides it. Closing the dashboard stops its service.

The active-cell count uses a 2 Hz threshold. For rendering, up to 6,000 active
cells plus the GF neurons are transmitted; filtering and missing soma coordinates
can reduce the visible count. All 165,122 modeled cells continue to be simulated.
The selected 20 neuron arbors are reconstructions; the remaining geometry is a
cell-body point cloud. Colors and traces show simulated firing rates.

## New attempts and adaptation

An armed controller schedules a new run three seconds after game-over. The
countdown uses wall-clock time so it works with frozen game frames. The brain
must still be responding; F7 or Esc cancels the restart. Control resumes in the
new run without another F6. Winning an ending does not trigger a restart.

The planner excludes permanent trap entities from shooting targets and waits
for temporarily invulnerable enemies. Floor spikes block walking but do not
automatically block tears. Ineffective shooting triggers a change of position.
Burning fireplaces are observed separately from enemies and block walking and
flying routes, including item collection and door approaches (mod 1.2.1).

Experience is stored locally in `data/isaac_learning.json`:

- Combat tactics learn from observed enemy HP loss, room clears, player damage,
  elapsed combat time and deaths.
- Damage and repeated stalls add routing costs to cells, keyed by room geometry.
- Tactic preferences and hazard costs survive restarting the service.
- Manual play does not train the controller.

This is adaptation of an engineered planner. The MaleCNS synaptic weights stay
fixed. Game coordinates come from the mod; the sensory encoding and neural
readout are designed for this controller. It does not learn the game from pixels.
Victories or consistently improving performance have not been demonstrated.
Complex boss attacks, item effects and special characters can still cause failures.

## Validation

Run `.venv\Scripts\python.exe -m pytest tests -q`. The Lua harness currently
uses `resources/scripts/json.lua` from the locally configured Isaac installation.
Checks cover input release, room/session boundaries, frozen-frame restarts,
restart cancellation, trap filtering, neural gating and persistent adaptation.
These tests do not replace a full game run.

On September 16, a live session with mod 1.2.0 confirmed five automatic restarts
with resumed control, nine cleared combat rooms and 133 saved tactic updates.
The last death was caused by a fireplace omitted from observations; 1.2.1 adds
fire observations and route avoidance. That specific fix is covered by automated
checks and still needs a new live run. The results do not establish improving win rate.

The UI capture mode uses a running local Isaac service:

```powershell
.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path terrarium --script res://scripts/isaac_dashboard.gd -- --sim-port=9886 --qa-isaac
```

It writes the dashboard and full brain-window captures to `logs/` and exits.

## Source files

| File | Responsibility |
| --- | --- |
| `isaac_mod/main.lua` | Observations, input overrides and new attempts |
| `isaac_policy.py` | Routing, aiming, sensory encoding and neural readout |
| `isaac_learning.py` | Tactic preferences and spatial risk memory |
| `isaac_service.py` | Neural simulation and local game connection |
| `terrarium/scripts/isaac_dashboard.gd` | Isaac observer |
| `terrarium/scripts/brain_view.gd` | 3D neural activity |

Local paths, connection tokens, experience, runtime data and logs are ignored by Git.
