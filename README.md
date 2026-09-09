# Put It Back — Godot

Native Godot 4.7.2 portrait microgames, ported from the original HTML canvas / Capacitor project. Open `project.godot` and press F6/F5, or run the Windows executable.

Fix each scene within five seconds. Tap puzzles use a click or tap; books, pencils, the garden, and plate-size ordering use dragging with a mouse or one finger. Success and timeout both advance automatically. The main menu's **Choose Level** starts repeating practice rounds. Use **II**, Escape, or Android Back to pause; tap below the pause text to return to the menu. Best streak is saved locally. Touch and mouse use the same logical coordinates; portrait artwork is preserved with letterboxing.

- **Hexagons (19):** repeating solid-color rows form recognizable stripes. One to three disjoint pairs of neighboring tiles start exchanged. Tap either misplaced tile to exchange it with its neighbor and repair the stripe. Correct tiles stay unchanged.
- **Pencils (10) and books (22):** one item starts inserted out of order. Drag it to the appropriate position in the color sequence or book sequence. Items between its old and new positions shift; the highlighted slot previews the insertion. Valid incorrect insertions remain incorrect, while drops outside the row return the item to its previous position.
- **Garden (5):** bushes sit on the eight circles drawn into the background; one to three begin loose on the lawn. Drag a loose bush onto any empty circle. Occupied circles and drops away from a circle are rejected.
- **Plate stack (3):** five plates retain their correct vertical spacing. One to three begin shifted horizontally; tap their visible rims to center them.
- **Plate sizes (3b):** six different plate sizes form a stack ordered largest at the top to smallest at the bottom. Exactly two interior plates start exchanged; all other plates keep their proper slots. The topmost and bottommost plates remain fixed as references, and drops into those slots are rejected. Drag a visible interior rim to restore order in one or two insertion drags.
- **Cookie facing (20):** five cookies stack on the plate. One or two show their filling on the right instead of the left; tap them to face left.
- **Cookie shift (20b):** all cookies face left, with one or two shifted a little sideways. Tap to center them while preserving their heights. Both cookie variants use the original left/right sprites without rotating them upside down.

`scripts/puzzle_interaction.gd` implements pointer ownership, insertion reordering, baseplate placement, and neighbor swaps. `scripts/puzzle_tests.gd` exercises these through the actual mouse/touch input handler, including invalid drops, wrong insertions, pause and touch cancellation, extra fingers, and timeouts during dragging.

`scripts/stack_puzzles.gd` composes the plate and cookie variants. Stacks draw bottom-to-top, and input uses the sprite's alpha so transparent corners and hidden layers do not steal taps or drags. `scripts/stack_tests.gd` checks visible-rim input, horizontal-only corrections, correct facing, vertical size ordering, and one/two-drag solvability.

## Levels

All game inscriptions use the bundled Cooper Bold (`assets/fonts/COOPERB.TTF`), extracted from `Corel/COOPERB.zip`. Text has no outlines. The Play label and elevator numerals are drawn with this font instead of using the lettering baked into the original sprites.

There are 24 playable variants. The eight original variants remain: fireplace, tower windows, drawer handles, building windows, ribbon tiles, circle tiles, road manhole, and pills. The additional puzzles use the PNG sprites extracted from every supplied Corel ZIP: elevator buttons (2), plates (3 and 3b), garden (5), junction cover (6), switches (7), tools (9), pencils (10), ceramics (12), brickwork (15), parquet (17), hexagons (19), cookies (20 and 20b), bathroom tiles (21), and bookshelf (22). Original level numbers are preserved; no level 11 artwork was supplied. The second variants use internal IDs 103, 114, and 120, respectively.

`scripts/game.gd` owns the native renderer, round state, input, procedural original puzzles, and save data. `scripts/extra_levels.gd` composes the added scenes. `www/` and `android/` retain the original implementation for reference; Godot does not embed a web browser or use Capacitor. `Corel/` retains all original archives and drawing sources and remains Git-ignored as before. Extracted PNGs in `assets/new/` are included in the repository working tree.

## Build and verification

Install Godot 4.7.2 export templates. Android requires JDK 17, an Android SDK and a debug keystore configured in Godot Editor Settings. This machine already has them under `D:/Godot/Android/`.

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . -- --self-test
godot --path . -- --gallery
godot --headless --path . --export-release 'Windows Desktop'
godot --headless --path . --export-debug Android
```

Create `exports/windows` and `exports/android` before exporting. Windows uses an embedded PCK. Android uses the existing application ID `com.vdsystem.putitback` and includes ARMv7, ARM64, and x86_64. The APK is a debug-signed installable build, not a Play Store release. A store release requires the owner's release signing key. An older installation signed with a different certificate cannot be upgraded directly.

`--self-test` runs 20 randomized solves per variant through actual hit testing and checks all timeout transitions. `--gallery` captures rendered screenshots in `verification/`. `--level=22` opens a specific practice level. Build outputs, screenshots, Godot caches, and Corel working sources are ignored by Git. The existing repository history and origin remote are retained; changes are left uncommitted for review.
