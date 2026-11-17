# November levels — 17 November 2026

Version **1.6.0**, Android version code **15**, adds levels 27–29 for a total
of 31 playable variants. All three are included in random play and the level
picker. Telemetry records the new puzzle revision as 1.6.0.

## Source material

The three Downloads ZIPs contain 15 PNGs and no written gameplay instructions
or composition references. The layouts and actions below are inferred from
the supplied objects and the game's five-second puzzle format. PNGs are copied
unchanged into `assets/new/`; archive copies are retained in ignored `Corel/`.

| Archive | Assets | SHA-256 |
| --- | --- | --- |
| Put It Back Level27.zip | Background, table, chair, plant, plate | `EE7DCC3AECC83ECBA9BE4B124457859ED6FD8317FCADEEDD7871C80D24A57C7F` |
| Put It Back Level28.zip | Background and six knife shapes | `8239D149B647AF81C41C7D7ED717DAC38F9526E9319EA2CEA2C2C3478809BB18` |
| Put It Back Level29.zip | Background, stick, ice cream | `90259BA349751AA092656F73346610388C61B0920861212251BD619F958B31D4` |

## Implemented puzzles

- **27 — Dining chairs:** six chairs surround the supplied table. Six plates
  sit between its baked-in utensils, with the plant in the center. One or two
  chairs start turned 15 degrees. Tap a crooked chair to straighten it.
  Alpha-aware hit testing follows drawing order so the table blocks taps on
  covered chair surfaces and transparent corners do not accept taps.
- **28 — Knife shapes:** five knives start fitted into their matching tray
  silhouettes; one randomly selected knife sits on the upper work surface.
  Drag it into the matching shape. Other silhouettes and off-tray drops return
  it to its starting position. Fitted knives remain fixed. The shared pointer
  handler preserves cancellation, pause, second-finger ownership and timeout
  behavior for the new `fit` interaction mode.
- **29 — Ice creams:** three ice creams sit above wooden sticks. Exactly one
  starts shifted sideways by 120 art pixels (24 logical screen pixels). Tap it
  to center it. The artwork keeps its original proportions, and neighboring
  ice creams remain separated even in a disturbed starting layout.

Composition lives in `scripts/november_levels.gd`. The integration suite in
`scripts/november_levels_tests.gd` exercises 120 seeded mouse/touch rounds,
all six knife shapes, wrong/off-tray drops, fixed pieces, pause and touch
cancellation, second fingers, and timeouts during dragging. Existing picker
tests cover all 31 entries, and the general suite solves each level 20 times.

Gallery output includes `verification/level_27.png` through `level_29.png`,
their `solved_*.png` counterparts, and the expanded `level_select.png`.
The build pipeline produces `exports/windows/PutItBack.exe` and the
debug-signed `exports/android/PutItBack.apk`. Tests use simulated mouse/touch
events; physical Android device testing is not part of this update.

Validation: the final tools/build.ps1 run passed asset import, ads parsing,
telemetry tests, all 31 levels with 20 seeded solves each, the 120 new-level
mouse/touch rounds, gallery rendering, Windows export/startup, Android export,
and APK signature verification. New scene and picker screenshots were visually
reviewed. All 15 extracted PNGs were verified byte-for-byte against Downloads.
