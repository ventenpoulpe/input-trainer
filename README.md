# Input Trainer - VF Mode

A rhythm-game style trainer for practicing **Virtua Fighter** execution.

Record a combo (or load one), then play it back Guitar Hero style: your inputs scroll down a 4-lane highway and you press them in time. Every press is judged to the frame, so you can see exactly how early or late you are and drill until it's consistent.

Built with **Godot 4.7**.

---

## Features

- **Record your own sequences.** Recording starts on your first press, so there's no dead time at the start. Diagonals, simultaneous buttons (like P+G) and held inputs are all captured.
- **Frame-accurate judging.** Each input is rated **PERFECT**, **GREAT**, **GOOD** or **MISS**, and shows how many frames early or late you were (`-2f`, `+1f`).
- **Hold inputs.** Directions or buttons held for 15+ frames become hold inputs, and you must keep them held to the end.
- **Endless practice loop.** The sequence repeats automatically, with a match score for each loop and your best score shown at all times.
- **Keyboard or controller.** Works with gamepads, arcade sticks and fightpads. Pick your device from a dropdown, and your choice is remembered.
- **Full rebinding.** Change every key and button, including the record and play shortcuts.
- **Player 1 / Player 2 side.** Forward and back follow the side you choose, just like in the game.
- **Shareable XML files.** Sequences are plain, readable XML files you can save, edit and swap with friends.

---

## Getting started

### Download the application

1. Download the latest version from [Releases](https://github.com/ventenpoulpe/input-trainer/releases).
2. Unzip the archive you've downloaded to the folder of your choice.
   Avoid `C:\Program Files`, since the app saves your recordings next to the `.exe`.
3. Make sure to leave the **Sequences/** folder in the same folder as the exe file.

Requires Windows 10 or 11 and a reasonably recent graphics driver (the app uses Direct3D 12).

> [!WARNING]
> **"Windows protected your PC"**
> The executable isn't code-signed, so Windows SmartScreen may block it the first time you run it.
> To start it anyway, click **More info**, then **Run anyway**. You only need to do this once.
> If you'd rather not, you can [build it yourself](#building-the-executable) from the source code.

### Your first practice session

1. Click **LOAD XML ▾** and pick the included sample `VF5R-JEA-BNB-6K`.
2. Press **Space** (keyboard) or **L3** (controller) to start.
3. After a short countdown, hit each input as it crosses the line at the bottom of the track.
4. Press **Space** / **L3** again to stop.

---

## How to use it

### Recording a combo

1. Press **Backspace** (keyboard) or **R3** (controller), or click **RECORD**.
   The screen shows **ARMED**: nothing is recorded yet.
2. Perform your combo. **Your first press is time zero.**
3. Press **Backspace** / **R3** again to stop.
4. Click **SAVE XML**, give it a name, and it's saved to the `Sequences` folder.

> Tip: pressing record while it's still armed cancels it.

### Playing a sequence

Press **Space** / **L3** or click **PLAY**. A 1-second countdown appears, then inputs start falling. When a loop ends you get your score, a short 0.5 s pause, and the next loop starts.

### Reading the screen


<img width="1591" height="886" alt="image" src="https://github.com/user-attachments/assets/14517430-d480-4f41-8d38-9268d0e0e42b" />


| Lane | Color | What to press |
|---|---|---|
| Direction | White, with arrows | The direction shown by the arrow |
| **G** — Guard | Green | Guard |
| **P** — Punch | Blue | Punch |
| **K** — Kick | Orange | Kick |

- **Long bars** behind an input are **holds**: keep the input down until the bar ends.
- The circles on the hit line light up with what you're currently holding, which is handy for checking your inputs.
- **TIME** and **FRAME** (60 FPS) on the right show where you are in the sequence.

### Scoring

| Rating | Timing | Points |
|---|---|---|
| PERFECT! | within ±2 frames | 100% |
| GREAT | within ±4 frames | 75% |
| GOOD | within ±6 frames | 50% |
| MISS | outside ±6 frames | 0% |

- A completed hold gives an extra point (**HOLD OK**). Letting go too early gives a **DROP**.
- Pressing a button when nothing is there counts as **EXTRA** and lowers your score, so mashing doesn't pay.
- Extra direction movements are **not** penalized, since moving between directions naturally passes through others.

Your **best score** resets when you load or record a different sequence.

---

## Controls

All bindings can be changed in **SETTINGS / REBIND**.

| Action | Keyboard | Controller |
|---|---|---|
| Up | W | D-Pad Up / Left Stick |
| Down | S | D-Pad Down / Left Stick |
| Left | A | D-Pad Left / Left Stick |
| Right | D | D-Pad Right / Left Stick |
| Punch (P) | Y | X |
| Kick (K) | U | Y |
| Guard (G) | G | A |
| Record start/stop | Backspace | R3 (Right Stick Click) |
| Play start/stop | Space | L3 (Left Stick Click) |

Controller buttons use Xbox names (A = bottom face button). The keyboard shortcuts for Record and Play always work, even when a controller is selected.

### Rebinding

1. Open **SETTINGS / REBIND**.
2. Click a binding, then press the new key or button within 5 seconds (**Esc** cancels).
3. If that input was already used by another action, the two swap.
4. Click **Save** to keep your changes, **Cancel** to undo them, or **Reset** to restore the defaults.

### Other settings

| Setting | What it does | Default |
|---|---|---|
| SFX volume | Volume of hit sounds and effects | 80% |
| Button click sounds | Click sound on menu buttons | On |
| Input scroll time | How long inputs take to reach the hit line (lower = faster) | 1.2 s |
| Side | Player 1 (facing right) or Player 2 (facing left) | Player 1 |

Settings are saved in Godot's user data folder (`user://settings.cfg`).

---

## Sequence files

Sequences are stored in the `Sequences` folder:

- When running from the Godot editor: `Sequences/` inside the project.
- In an exported build: a `Sequences` folder next to the executable.

The **LOAD XML ▾** menu lists every file in that folder, and also has **Browse...** and **Open Sequences folder**.

### File format

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

- **timestamp**: seconds from the first press. **frame**: the same time at 60 FPS.
- **Direction**: what's held at that moment, in VF notation relative to facing:
  `NEUTRAL`, `UP`, `DOWN`, `FORWARD`, `BACK`, `UP_FORWARD`, `UP_BACK`, `DOWN_FORWARD`, `DOWN_BACK`.
- **Buttons**: the buttons newly pressed at that moment (`P`, `K`, `G`).
- **hold** (optional): how long the input is held, in seconds.

Files using the older `<InputNote>` tag still load.

---

## Building the executable

The project includes a Windows export preset (`export_presets.cfg`) and a build script (`build.ps1`).

**One-time setup:** open the project in Godot 4.7, then go to **Editor → Manage Export Templates → Download and Install**.

**Build:**

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_win64.exe" -Zip
```

You can also set the `GODOT` environment variable to the Godot path and leave out `-Godot`.

Output in `build/`:

```
build/
  InputTrainer.exe          the app (game data embedded)
  Sequences/                sample sequences, copied from the project
  InputTrainer-win64.zip    with -Zip: ready to attach to a GitHub Release
```

Rebuilding keeps any recordings already saved in `build/Sequences`.

You can also export from the editor with **Project → Export… → Windows Desktop → Export Project**. In that case, copy the `Sequences` folder next to the `.exe` yourself.

---

## Project structure

```
autoload/      Global services: settings, input bindings, sequence manager, sound effects
gameplay/      Practice loop and timing judge (ratings and scoring)
sequence/      Sequence data, recorder and XML reader/writer
ui/            Highway, countdown, device selector, save dialog, settings menu
Sequences/     Sequence XML files
main.tscn      Main screen
build.ps1      Builds the Windows executable (see above)
export_presets.cfg  Godot export settings
specs.md       Full technical and functional specification
```

See [specs.md](specs.md) for the full specification.
