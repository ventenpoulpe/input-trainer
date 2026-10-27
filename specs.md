# Input Trainer - VF Mode — Technical & Functional Specifications

## 1. System Overview

- **Application name:** Input Trainer - VF Mode
- **Target platform:** PC / Desktop (Windows, Direct3D 12)
- **Engine:** Godot 4.7 (Forward+), GDScript. Base resolution 1600×900, `canvas_items` stretch with `expand` aspect.
- **Core concept:** A rhythm/timing trainer inspired by Guitar Hero, built for practicing fighting game execution using Virtua Fighter notation: 8-way directions (relative to facing) plus Punch (P), Kick (K) and Guard (G).

### 1.1 Code Layout

| Path | Role |
|---|---|
| `autoload/user_settings.gd` (`UserSettings`) | Single settings file `user://settings.cfg`: bindings, device, preferences. |
| `autoload/input_config.gd` (`InputConfig`) | Bindings, active device, InputMap rebuild. |
| `autoload/sequence_manager.gd` (`SequenceManager`) | Current sequence, recorder, load/save, sequences folder. |
| `autoload/sfx.gd` (`Sfx`) | Sound effects synthesized at startup (no audio files). |
| `sequence/` | `SequenceInput`, `InputSequence`, `SequenceRecorder`, `SequenceXml`. |
| `gameplay/` | `GameplayController` (loop state machine), `TimingJudge` (targets, ratings, score). |
| `ui/` | `Highway`, `CountdownRing`, device dropdown, save dialog, settings menu. |
| `main.tscn` / `main.gd` | Main screen: toolbar, HUD, highway. |
| `Sequences/` | Sequence XML files. |

## 2. User Workflows & Modules

### 2.1 Settings & Controls Module

**Active device selection**
- A dropdown in the toolbar lists `Keyboard` first, then every connected controller as `<name> (#n)` (Godot joypad API, SDL mapping).
- Only the active device drives the game inputs (directions + P/K/G).
- The chosen controller is remembered by GUID. It is re-selected automatically when it reconnects. If the active controller disconnects, the app falls back to the keyboard (the controller stays remembered).

**Bindings**
- Each action has one keyboard binding and one controller binding.
- Controller bindings can be a button or a stick/trigger direction (capture threshold 0.6, action deadzone 0.5).
- Option **Use left stick for directions** (on by default): adds the left analog stick on top of the controller direction bindings.
- App shortcuts (Record / Play) also accept their keyboard binding while a controller is active.

**Rebinding (Settings / Rebind menu)**
- Modal overlay with a grid: `INPUT | KEYBOARD | CONTROLLER`, then a `SHORTCUTS` section.
- Click a binding, then press the new key/button within **5 seconds** (countdown shown on the button). Esc or clicking the same button cancels.
- If the new input is already used by another action, the two actions **swap** bindings (reported in the status line).
- Changes apply immediately so they can be tried out.
- **Save** writes everything to `user://settings.cfg`. **Cancel** (or Esc) reverts to the last saved state. **Reset** restores default bindings and preferences (Save is still needed to keep them).
- Gameplay and recording ignore input while a rebind is waiting.

**Default control mappings**

| Input function | Keyboard default | Controller default |
|---|---|---|
| Up | W | D-Pad Up / Left Stick Up |
| Down | S | D-Pad Down / Left Stick Down |
| Left | A | D-Pad Left / Left Stick Left |
| Right | D | D-Pad Right / Left Stick Right |
| Punch (P) | Y | X |
| Kick (K) | U | Y |
| Guard (G) | G | A |
| Record Toggle | Backspace | R3 (Right Stick Click) |
| Play Toggle | Space | L3 (Left Stick Click) |

Controller button names follow the Xbox layout (A = bottom face button). Keyboard bindings use physical key codes and are displayed with the current keyboard layout.

**Preferences (also in the Settings menu)**

| Preference | Range | Default |
|---|---|---|
| SFX volume | 0–100 %, step 5 | 80 % |
| Button click sounds | on / off | on |
| Input scroll time (seconds for an input to reach the hit line; lower = faster) | 0.5–2.5 s, step 0.1 | 1.2 s |
| Side | Player 1 (facing right) / Player 2 (facing left) | Player 1 |

The Side preference decides how left/right map to FORWARD/BACK when recording and judging, and flips the direction arrows on screen so they always show the physical direction to press.

**Settings file:** `user://settings.cfg` with sections `[keyboard]`, `[joypad]`, `[input]` (`use_left_stick`, `joy_guid`), `[audio]`, `[gameplay]`. Older `user://controls.cfg` / `user://device.cfg` files are imported once if `settings.cfg` is missing.

### 2.2 Sequence Management Module

**Sequences folder**
- Run from the editor: `res://Sequences/`.
- Exported build: a `Sequences` folder next to the executable (created if missing).

**Load XML** (`LOAD XML ▾` menu)
- The menu rescans the sequences folder each time it opens and lists every `.xml` file by name (natural sort); the current file is checked.
- `Browse...` opens a file dialog filtered to `*.xml`.
- `Open Sequences folder` opens the folder in the system file browser.
- Loading cancels any recording in progress. Load errors (missing file, malformed XML, missing `<InputSequence>`, non-numeric timestamp) are shown in the status line. Unknown directions become `NEUTRAL`; unknown buttons are skipped (with a warning).

**Record** (toggle with the RECORD button or the Record shortcut)
- Toggle cycles: **idle → armed → recording → stopped**. Toggling while armed cancels.
- **Armed:** waits for the first new press (a direction other than neutral or a button). Inputs already held when arming don't count. That first press is **t = 0.0 s / frame 0**.
- **Recording:** every direction change or new button press creates an input. Changes less than one frame apart (16.667 ms) are merged into one input, so diagonals and simultaneous buttons (e.g. P+G) record together.
- **Hold inputs:** a direction or button kept down for at least **15 frames** (0.25 s) gets a hold length on the input where it was pressed. Directions or buttons still held when recording stops end at that moment.
- **Stop:** the recording becomes the current, unsaved sequence (author `Player1`). If nothing was pressed, the previous sequence is kept. Duration = time of the last input change, extended to cover the end of any hold.
- Starting playback while recording is refused ("Stop recording first").

**Save XML**
- Disabled until a sequence is loaded or recorded.
- Opens a dialog with **File name** and **Author** (defaults to `Player1`). The name is sanitized (a trailing `.xml` is stripped, invalid characters replaced). The hint line shows the target path and warns when it will overwrite an existing file.
- Saves to `<sequences folder>/<name>.xml`; the sequence's `name` attribute is set to the file name.

**Actions that stop other activity:** opening the Load menu, Save dialog or Settings menu stops playback. A recording in progress is stopped and kept (or cancelled if only armed).

**XML format**

```xml
<?xml version="1.0" encoding="utf-8"?>
<InputSequence name="Jean_Kujo_BnB01" author="Player1" duration="4.500">
    <Input timestamp="0.000" frame="0">
        <Direction>FORWARD</Direction>
        <Buttons></Buttons>
    </Input>
    <Input timestamp="0.300" frame="18">
        <Direction hold="0.400" holdFrames="24">DOWN_FORWARD</Direction>
        <Buttons>
            <Button>P</Button>
            <Button hold="0.300" holdFrames="18">G</Button>
        </Buttons>
    </Input>
</InputSequence>
```

- Times are in seconds with 3 decimals; `frame` = round(timestamp × 60).
- `Direction` is the full direction held at that moment (it can repeat across inputs) and is one of: `NEUTRAL`, `UP`, `DOWN`, `FORWARD`, `BACK`, `UP_FORWARD`, `UP_BACK`, `DOWN_FORWARD`, `DOWN_BACK`. Opposite directions held together cancel out.
- `Buttons` lists the buttons **newly pressed** at that moment, saved in `P, K, G` order.
- `hold` (seconds) is optional and marks a hold input; `holdFrames` is written for readability only. Files without holds use the plain schema. Files using the older `<InputNote>` tag still load.
- On load, inputs are sorted by timestamp and `duration` is raised if needed to cover the last input/hold. A missing `name` falls back to the file name.

### 2.3 Gameplay & Timing Evaluation Module

**Loop state machine** (`GameplayController`)

`STOPPED → COUNTDOWN (1.0 s) → PLAYING → LOOP_PAUSE (0.5 s) → PLAYING → ...`

- Play toggles with the PLAY button or the Play shortcut (button label becomes `STOP` while running).
- Refused with a status message if there is no sequence or it has no playable inputs.
- **Countdown:** 1.0 s with a circular progress ring labelled `READY` in the middle of the highway, plus a "ready" sound.
- **Playing:** each loop starts at `-scroll time` so the first inputs can scroll down to the hit line. Directions or buttons already held when a loop starts don't count as presses.
- **Loop end:** after the sequence duration (or the last input + the GOOD window, whichever is later). Shows `LOOP n: XX.X%` (plus `NEW BEST!`) on the highway during the 0.5 s pause, then restarts.

**Targets** (`TimingJudge`)
- 4 lanes: Direction, G, P, K.
- A direction target is created only when an input's direction differs from the previous input's. `NEUTRAL` is never a target but still counts as a change (FORWARD, NEUTRAL, FORWARD = 2 targets).
- A button target is created for each button pressed in an input.
- Hold inputs are scored twice: the press (like any input) and the release.

**Timing windows** (60 FPS frames, measured from the input time)

| Rating | Window | Points |
|---|---|---|
| PERFECT! | ≤ ±2 frames (±33.3 ms) | 1.0 |
| GREAT | ≤ ±4 frames (±66.7 ms) | 0.75 |
| GOOD | ≤ ±6 frames (±100 ms) | 0.5 |
| MISS | not hit within ±6 frames | 0 |

- A press hits the closest unjudged target in its lane within the GOOD window (direction presses must match the target direction).
- **Holds:** releasing at or after `hold end − 6 frames` (or holding past the end) = `HOLD OK` (+1 point). Releasing earlier = `DROP` (0). A missed hold press also loses its release point.
- **Extra presses:** a button press with no target in reach counts against the score (prevents mashing). Extra direction changes are not penalized, since moving between directions naturally passes through others.

**Match rate** = points earned / (items judged + extra button presses) × 100, calculated per loop.

**Best score**
- Best match rate across loops, shown in the toolbar and HUD.
- Reset when a new sequence is loaded or recorded, or when a recording starts. Not saved between sessions.

**Feedback**
- Popup text above the lane's receptor: `PERFECT!` / `GREAT` / `GOOD` / `MISS`, with the frame offset (e.g. `-2f` early, `+1f` late) when not exactly on time. Also `EXTRA`, `HOLD OK`, `DROP`. A new popup replaces the previous one in the same lane.
- GPU spark burst and an expanding ring flash at the receptor on each hit and successful hold; a continuous spark stream and pulsing glow while a hold is being held.
- Rating colors: PERFECT gold, GREAT green, GOOD light blue, MISS red.
- Sounds (synthesized): per rating, extra press, hold ok/drop, countdown "ready", loop end, new best arpeggio, and UI button clicks (optional).

## 3. UI & Visual Layout Specifications

### 3.1 Top Toolbar

Left to right:

`[ LOAD XML ▾ ] [ RECORD (START/STOP) ] [ SAVE XML ] [ PLAY (START/STOP) ] | Active Device: [ Keyboard ▼ ] [ SETTINGS / REBIND ] ...... BEST MATCH SCORE: XX.X%`

- RECORD button label follows the state: `RECORD (START/STOP)` → `CANCEL RECORD` (armed) → `STOP RECORD` (recording).
- Scores show `--` when there is no value yet.

Below the toolbar: centered title **INPUT TRAINER: VF MODE**.

### 3.2 HUD

**Left column (stats)**
- `MATCH: XX.X%` (current loop, `--` when stopped)
- `BEST: XX.X%`
- `CURRENT LOOP PROGRESS: XX%`
- `LOOP: n`
- Rating counts while running: `PERFECT n  GREAT n / GOOD n  MISS n  EXTRA n`, plus `HOLD OK n  DROP n` when the sequence has holds
- Status line at the bottom (load/save results, errors, hints)

**Right column (info & timers)**
- `FILE: <filename>.xml` (or `(unsaved recording)`, or `-`)
- `TIME: X.XX s`
- `FRAME: N f` (60 FPS)
- Recording label, only while recording is active: `ARMED` / `first input starts recording` (two lines), then `RECORDING...`

TIME/FRAME show the elapsed recording time while recording, the sequence time while playing, and the sequence duration otherwise.

### 3.3 Highway

- 4-lane track drawn in 2D with a perspective projection (far end is 30 % of the hit-line width). Inputs fade in near the far end and scroll toward the hit line over the scroll time.
- Moving grid lines every 0.25 s (brighter every second) show the scroll speed.

| Lane | Header | Inputs |
|---|---|---|
| 1 — Direction | Joystick icon | Dark tile with an arrow (8 directions, flipped on the P2 side) |
| 2 — Guard (G) | Green `G` badge | Green tiles |
| 3 — Punch (P) | Blue `P` badge | Blue tiles |
| 4 — Kick (K) | Orange `K` badge | Orange tiles |

- **Hold inputs:** a bar trails behind the tile to the hold's end. While held, the bar is eaten at the hit line and glows; dropped holds turn grey.
- Hit inputs disappear; missed inputs stay visible in grey and scroll past.
- **Hit line:** translucent bar across the track with one circular receptor per lane. Receptors light up with the live input (the direction receptor shows an arrow of the held direction; button receptors show their letter).
- **Messages on the highway when stopped:** `Load or record a sequence` or `Press PLAY (Space / L3) to practice`.
