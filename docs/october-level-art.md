# October level artwork — 9 October 2026

Version **1.5.2**, Android version code **14**.

| Downloads archive | Contents | Result |
| --- | --- | --- |
| `Put It Back Level26.zip` | `Picture_Level26.png`, 2500 × 5000 | Replaces the low-resolution comparison-image crop in the dessert picture puzzle. |
| `Background Level10.zip` | `Background_Level10.png`, 2500 × 5000 | Byte-identical to the background already in `assets/new/`; the lowered pencil tray from version 1.4.0 is already implemented. |

Level 26 uses the complete original PNG without cropping or recreating the art.
Its 4 by 8 grid consists of 625 × 625 source regions. One or two pairs begin swapped;
dragging exchanges tiles, and restoring every tile solves the round. Existing
interaction, cancellation and timeout behavior is preserved. The September JPEG
remains in the repository as a historical reference and is no longer the puzzle's
texture source.

Level 10 retains the supplied background and the existing pencil row at y=1230 in
artwork coordinates. The archive does not contain a further background revision.

Imported source SHA-256 values:

```text
Picture_Level26.png
26a0e72b2c71b3000c84d90fadf93e40696f9d4777c73b84c8c162e36ce9853b

Background_Level10.png
a9cc9c85078058f3d9d3f95b15e4710ced296f4c36fb9fe0f1246e600f059640
```

The game-wide telemetry puzzle revision advances to 1.5.2 so newly collected rounds
can be distinguished from those using the previous artwork. Previously queued
events retain their original version and revision.

## Validation

`tools/build.ps1` passed asset import, Android ads parsing, telemetry tests, all
28 levels with 20 randomized solves each, interaction and timeout checks, gallery
rendering, Windows export/startup, and Android export/signature verification.
The solved gallery images for levels 10 and 26 were visually inspected.

The debug-signed Android 1.5.2 APK was installed over the normal
`com.vdsystem.putitback` app on the connected Samsung Galaxy S24+ (SM-S926B,
Android 16). Both levels were inspected on the phone; dragging the misplaced
dessert tiles restored the picture and displayed the success message. The saved
best streak remained 27 before and after installation and testing. The app log
contained no Godot script errors or fatal exceptions. The separate QA app was
not updated. This device installation is not a store release.

Build artifacts are in `exports/`; local gallery images and device screenshots
are in `verification/`. Both directories are Git-ignored.
