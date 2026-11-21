# Level 30 — Bedtime

Implemented November 21, 2026, in version **1.7.0** (Android version code **18**).
There are **34 playable variants**, including the November feedback changes
documented in [November feedback](november-feedback.md).

## Source artwork

`Downloads/Put It Back Level30.zip` contains seven PNGs: the bedroom background,
a pillow, three cover states, and on/off lamp sprites. All seven are copied
unchanged into `assets/new/`; the original ZIP is retained in ignored `Corel/`.
Archive SHA-256:
`69D1AA5D933214456C8F904D72EC51B06956A5411DF1AC0660F900A401F3CDA0`.

The archive has no written gameplay instructions or composition reference.
The following action and placement are inferred from the artwork and the
game's five-second round format.

## Gameplay and layout

The bed has two pillows and a cover, with a lamp on each bedside table.
One or two objects begin faulty. Tap a crooked pillow to straighten it,
either rumpled cover state to restore the flat cover, or a lit lamp to turn
it off. Correct objects stay unchanged. Sprite-alpha hit testing rejects
transparent corners, and the shared input handler supports mouse and touch.

The cover follows the mattress width and ends at its foot. Pillows sit just
below the headboard; all sprites retain their source proportions. Level 30
is available in random play and Choose Level, with the normal pause,
five-second timeout, and automatic round progression.

## Validation

The dedicated tests run 80 seeded mouse/touch rounds and cover both rumpled
cover images, crooked pillows, lit lamps, correct-object taps, transparent
corners, empty-space taps, pause, completion and input after timeout.
The shared suite covers picker access and 20 solves for all 34 variants.
Gallery images include `verification/level_30.png`, `solved_30.png`, and
the updated level picker. The source PNGs were verified byte-for-byte.

`tools/build.ps1` passed asset import, ads parsing, telemetry tests, the full
game suite, gallery rendering, Windows export/startup, Android export, and
APK signature verification. Starting/solved bedroom screenshots and the
picker were visually reviewed. No physical-device installation was performed.
