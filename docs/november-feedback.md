# November 17 feedback — implemented November 20, 2026

Version **1.6.2**, Android version code **17**, completes Ana's feedback using
the new archive and both reference images. There are **33 playable variants**.

- **7b — Eight switches (internal ID 107):** two rows of four switches,
  matching the supplied reference with adjacent frames and a gap between rows.
  One or two levers start down; tap them
  to switch up. The original three-switch level 7 remains available. Both
  variants appear in random play and Choose Level.
- **9b — Tool sizes (internal ID 109):** six wrenches increase in size from
  left to right, with their ring openings aligned on the mounting rail as in
  the reference. One or two start crooked; tap to straighten them, retaining
  the existing level 9 interaction. The original three-wrench variant remains.
- **17 — Grocery shelf:** replaces the parquet puzzle with three shelves and
  fifteen products from the replacement pack. One or two products show their
  backs; tap to turn their labels forward. The archive supplies five paired
  front/back sprites, a background, and three shelf sections. No composition
  reference or written mechanic was supplied for this level, so the layout
  and label-facing action are inferred from those assets. The 14 PNGs are
  preserved byte-for-byte in `assets/new/`.
- **18 — Pills:** replaces `www/assets/Background_Level18.png` with the exact
  PNG from `Downloads/Background Level18.zip`. The replacement confines the
  crosshatch pattern to the rounded gray backing, fixing the right edge.
  The pill layout and interaction are unchanged.

The source ZIP is retained in ignored `Corel/Background Level18 November.zip`.
The extracted PNG SHA-256 is
`DE173FCC8B385BC31C8FA89131274A10E84D1DD05D599E77DC47E8A1780E4C23`.

## Additional source files

- `Downloads/Put It Back Level17 New.zip`, retained in ignored `Corel/`.
  SHA-256: `B5DF432F5E72B4DF6BA14654CEE0FCB296E9754570B2F1D493F089897AC04CCB`.
- `viber_image_2026-11-17_15-35-20-823.png` is preserved as
  `assets/new/Tools_November_Reference.png`.
- `viber_image_2026-11-17_15-44-23-350.png` is preserved as
  `assets/new/Switches_November_Reference.png`. This reference establishes
  eight switches, superseding the provisional six-switch layout in 1.6.1.

## Verification

The switch regression checks cover 40 seeded rounds using alternating mouse
and touch input, correct-switch taps, and completion in both layouts. Another
80 rounds cover level 17 and 9b, including all five grocery backs, taps on
correct products and empty space, completion, and timeout. The shared tests
exercise picker access, 20 solves per variant, and timeouts. Gallery captures
include starting and solved versions of 7b, 9b and 17, plus the updated picker.

The 1.6.2 asset import, ads parsing, telemetry tests, all 33 variants with
20 solves each, gallery rendering, Windows export/startup, and Android
export/signature verification passed through `tools/build.ps1`.
The level 7b, level 9b, level 17
and picker screenshots were visually reviewed. All replacement artwork was
verified byte-for-byte against the supplied PNGs. Device installation was
not performed.
