Input Trainer - VF Mode — Technical & Functional Specifications
1. System Overview
Application Name: Input Trainer - VF Mode
Target Platform: PC / Desktop
Core Concept: A rhythm/timing training game inspired by Guitar Hero, specifically tailored for practicing and mastering fighting game execution using Virtua Fighter notation and inputs (4-way/8-way Directions + Punch P, Kick K, Guard G).
2. User Workflows & Modules
2.1 Settings & Controls Module
Active Controller Selection: Auto-detects and lists all connected keyboards and DirectX/XInput controllers (gamepads, arcade sticks, fightpads) via an on-screen dropdown menu.
Key & Button Rebinding: Fully customizable mapping for the 4 cardinal/directional inputs, 3 action buttons (P, K, G), and application shortcuts with save/reset-to-default functionality.
Application Shortcuts:
Record Start/Stop Toggle: Default is Backspace on keyboard / R3 (Right Stick Click) on controller.
Play Sequence Start/Stop Toggle: Default is Spacebar on keyboard / L3 (Left Stick Click) on controller.
Default Control Mappings:
Input Function
Keyboard Default
Controller Default (XInput/DirectInput)
 
Up
W
D-Pad Up / Left Analog Up
Down
S
D-Pad Down / Left Analog Down
Left
A
D-Pad Left / Left Analog Left
Right
D
D-Pad Right / Left Analog Right
Punch (P)
Y
X Button
Kick (K)
U
Y Button
Guard (G)
G
A Button
Record Toggle
Backspace
R3 (Right Stick Click)
Play Toggle
Spacebar
L3 (Left Stick Click)

2.2 Sequence Management Module
Load XML: Load pre-recorded XML sequence files from the local directory.
Record (Start/Stop): Capture player input sequences in real-time. Recording begins precisely on the player's first input press (t = 0.0s / Frame 0). Supports simultaneous inputs (diagonals + multiple buttons).
Save XML: Save recorded sequences into XML format under a user-defined filename.
<?xml version="1.0" encoding="utf-8"?>
<InputSequence name="Jean_Kujo_BnB01" author="Player1" duration="4.5">
    <InputNote timestamp="0.00" frame="0">
        <Direction>FORWARD</Direction>
        <Buttons></Buttons>
    </InputNote>
    <InputNote timestamp="0.30" frame="18">
        <Direction>DOWN_FORWARD</Direction>
        <Buttons>
            <Button>P</Button>
            <Button>G</Button>
        </Buttons>
    </InputNote>
</InputSequence>


2.3 Gameplay & Timing Evaluation Module
Pre-Game Readiness: Starting a sequence triggers a 1.0-second delay featuring a real-time circular progress indicator before notes begin descending.
Highway & Target Hit Line: Notes travel down a 4-lane 3D perspective track toward the bottom target hit line.
Timing Windows & Rating: Inputs are evaluated against note timestamps (e.g., PERFECT within ≤ ±16.67ms / 1 frame to ±33.33ms / 2 frames). Triggers dynamic particle spark effects and text feedback (PERFECT!).
Real-time Timer & Frame Counter: Real-time display on the right side of the screen HUD tracking sequence timing both in seconds (TIME: X.XX s) and in frame numbers at 60 FPS (FRAME: N f).
Scoring & Loop Behavior:
Calculates the Matching Rate percentage per loop iteration.
After a loop finishes, pauses for 0.5 seconds before restarting.
Displays the Best Matching Score continuously in the UI bar until a new sequence file is loaded or a new recording starts.
Recording: when recording is active, a label RECORDING… should be displayed on the right side of the tracks.
3. UI & Visual Layout Specifications
3.1 Top Control Panel & Toolbar Bar
The top section of the screen integrates quick management controls and device configuration options:
Top Control Buttons: [ LOAD XML ], [ RECORD (START/STOP) ], [ SAVE XML ]
Device Dropdown: Active Device: [ Xbox Controller / Keyboard ▼ ]
Configuration Button: [ SETTINGS / REBIND ]
High Score Display: BEST MATCH SCORE: XX.X%
3.2 Complete HUD & Track Layout
Top-Left Corner Stats:
MATCH: XX%
BEST: XX%
CURRENT LOOP PROGRESS: XX%
Top-Center Title: INPUT TRAINER: VF MODE
Top-Right Corner Info & Timers:
FILE: <filename>.xml
TIME: X.XX s (Sequence elapsed time in seconds) [cite: 3]
FRAME: N f (Sequence elapsed time in 60 FPS frames) [cite: 3]
4-Lane Highway Layout (Left to Right):
Lane 1 (Directional Track): Header features a Joystick icon; notes render as directional arrows (cardinals and diagonals) [cite: 3].
Lane 2 (Guard - G): Header features a green G badge; notes render as green tiles [cite: 3].
Lane 3 (Punch - P):** Header features a blue P badge; notes render as blue tiles [cite: 3].
Lane 4 (Kick - K): Header features a red K badge; notes render as red/orange tiles [cite: 3].
Timing Zone: Translucent horizontal hit bar across the base of the highway with spark emission particle effects on successful hits [cite: 3].
Concept (timing zone not showing recording/settings features not showing here)

