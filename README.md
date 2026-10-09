# Put It Back — Godot

Native Godot 4.7.2 portrait microgames, ported from the original HTML canvas / Capacitor project. Open `project.godot` and press F6/F5, or run the Windows executable.

The [complete backend documentation](backend/README.md) covers architecture, API events, dashboard metrics, operations and backup/recovery. The [client integration guide](backend/docs/client-integration.md) documents the implemented Godot telemetry, configuration, collection controls, offline delivery and tests. The [deployment record](docs/telemetry-deployment.md) records the server setup; the [telemetry plan](docs/telemetry-plan.md) preserves the broader roadmap.

The backend has separate **Game KPIs** and **Game QA (test data)** dashboards. The QA dashboard shows test sessions, level outcomes, ad callbacks and delivery status. See [dashboard access](backend/docs/dashboard-access.md) for browser links and instructions for this PC or another computer on the server's local network; a local-network computer with SSH access does not need OpenVPN.

Version **1.5.0** adds optional first-party analytics. Use **Usage data** on the main menu to allow or stop collection. It starts off. Configured native release builds report rounds, playtime and ad events over HTTPS, with a persistent offline queue. Editor/debug runs are disabled unless explicitly started with `--telemetry-test`, which uses a separate test identity. The standard Android debug APK therefore has collection disabled. See the [configuration and release instructions](backend/docs/client-integration.md#build-configuration) before shipping.

Version **1.5.1** fixes Android Back closing the app from the level picker or usage screen, and fixes telemetry undercounting active time on high-refresh-rate phones. A separate Android QA build supports device testing without replacing the normal app. See the [Android validation record](docs/android-telemetry-validation.md).

Version **1.5.2** replaces level 26's screenshot-based dessert image with the supplied 2500 × 5000 PNG, preserving the 4 by 8 tile-swap puzzle. The level 10 ZIP matches the pencil background already integrated in 1.4.0. Both supplied archives are recorded in the [October artwork notes](docs/october-level-art.md).

Fix each scene within five seconds. Tap puzzles use a click or tap; books, pencils, paint tubes, juice bottles, and the garden use dragging with a mouse or one finger. Success and timeout both advance automatically. The main menu's **Choose Level** starts repeating practice rounds. Use **II**, Escape, or Android Back to pause; tap below the pause text to return to the menu. Best streak is saved locally. Touch and mouse use the same logical coordinates; portrait artwork is preserved with letterboxing.

- **Hexagons (19):** blue petals surround red centers in a full-screen flower pattern, with cream tiles between flowers. A red center and a cream tile start exchanged. Tap either misplaced tile to restore the pair. Correct tiles stay unchanged.
- **Pencils (10) and books (22):** one item starts inserted out of order. Drag it to the appropriate position in the color sequence or book sequence. Items between its old and new positions shift; the surrounding objects preview the insertion without a yellow highlight. Valid incorrect insertions remain incorrect, while drops outside the row return the item to its previous position.
- **Garden (5):** bushes sit on the eight circles drawn into the background; one begins slightly offset beside its own circle. Drag a loose bush onto any empty circle. Occupied circles and drops away from a circle are rejected.
- **Plate stack (3):** five plates retain their correct vertical spacing. One to three begin shifted horizontally; tap their visible rims to center them.
- **Cookie facing (20):** five cookies stack on the plate. One or two show their filling on the right instead of the left; tap them to face left.
- **Cookie shift (20b):** all cookies face left, with one or two shifted a little sideways. Tap to center them while preserving their heights. Both cookie variants use the original left/right sprites without rotating them upside down.

`scripts/puzzle_interaction.gd` implements pointer ownership, insertion reordering, baseplate placement, and neighbor swaps. `scripts/puzzle_tests.gd` exercises these through the actual mouse/touch input handler, including invalid drops, wrong insertions, pause and touch cancellation, extra fingers, and timeouts during dragging.

`scripts/stack_puzzles.gd` composes the plate and cookie variants. Stacks draw bottom-to-top, and input uses the sprite's alpha so transparent corners and hidden layers do not steal taps or drags. `scripts/stack_tests.gd` checks visible-rim input, horizontal alignment, and cookie facing.

## Levels

All game inscriptions use the bundled Cooper Bold (`assets/fonts/COOPERB.TTF`), extracted from `Corel/COOPERB.zip`. Text has no outlines. The Play label and elevator numerals are drawn with this font instead of using the lettering baked into the original sprites.

There are 28 playable variants. The eight original variants remain: fireplace, tower windows, drawer handles, building windows, ribbon tiles, circle tiles, road manhole, and pills. The additional puzzles use the supplied artwork: elevator buttons (2), plates (3), garden (5), junction cover (6), switches (7), tools (9), pencils (10), cakes (11), ceramics (12), brick arch (15), parquet (17), hexagons (19), cookies (20 and 20b), bathroom tiles (21), bookshelf (22), paint tubes (23), juice bottles (24), drawers (25), and dessert picture (26). Original level numbers are preserved; the previously unnumbered dessert picture is assigned 26. The circle and cookie-shift variants use internal IDs 114 and 120. Plate-size ordering (103) has been removed.

The September art packs add four puzzles, available in both random play and the level picker:

- **Cakes (11):** tap the single off-center cake to center it on its plate.
- **Paint tubes (23):** drag a displaced tube into color order, reading left to right across the top row, then the bottom row. The palette supplies the color sequence: white, yellow, orange, red, pink, purple, blue, cyan, light green, dark green, brown, black. Other tubes shift to preview the insertion, including across rows. One correct insertion solves the round; incorrect insertions remain playable, and drops outside the tray return to the previous order.
- **Juice bottles (24):** two opposite flavors start with their positions exchanged. Drag one bottle onto the other to swap them back: lemon on the left, grape on the right. Any pair can be swapped; identical flavors are interchangeable, incorrect swaps remain playable, and drops outside a bottle return to the original slot.
- **Drawers (25):** tap the one or two open drawers to close them. A fully open drawer takes two taps, passing through the partly open sprite.

`scripts/new_levels_tests.gd` verifies menu reachability, the new artwork, mouse/touch input, cross-row paint insertion, bottle exchanges, drawer opening depths, and timeout behavior. Gallery captures include the expanded picker, paint and bottle drag previews, and solved versions of the new scenes.

Version 1.3.1 increases horizontal alignment faults for the lighthouse, house windows, drawer handles, fireplace, cakes, bathroom tiles, and plate/cookie stacks. Small objects shift roughly 20–25 pixels at the 500-pixel game width; larger objects shift farther, while cakes stay on their plates. Three-object scenes still have exactly one faulty object.

Version 1.3.2 uses the replacement backgrounds supplied on September 23 for plates (3) and tools (9), correcting the tabletop and mounting-strip positions.

Version 1.4.0 follows the September 29 references:

- **Brick arch (15):** two fixed pillars support a stepped arch. One upper course begins shifted horizontally; tap it to center the whole course.
- **Hexagons (19):** the flower layout replaces the earlier stripes and fills the screen as shown in the reference.
- **Dessert picture (26):** drag square fragments to swap their positions and restore the image. One or two pairs begin exchanged. Valid wrong swaps remain playable; off-board drops and canceled drags restore the previous position.
- **Pencils (10):** the replacement background lowers the tray; the pencils move with their slots.
- **Elevator (2):** numbered and control buttons are centered on the circular mounts drawn into the background.
- **Drawers (25):** upper drawers render in front of the row below when open, and hit testing follows the visible sprite surface.

Source details and interpretation of the reference images are recorded in [the September reference notes](docs/september-reference-levels.md). The dessert picture now uses the complete original PNG through Godot atlas regions; the old comparison JPEG is retained only as a historical reference.

`scripts/game.gd` owns the native renderer, round state, input, procedural original puzzles, and save data. `scripts/extra_levels.gd` composes the added scenes. `www/` and `android/` retain the original implementation for reference; Godot does not embed a web browser or use Capacitor. `Corel/` retains all original archives and drawing sources and remains Git-ignored as before. Extracted PNGs in `assets/new/` are included in the repository working tree.

## Build and verification

Install Godot 4.7.2 export templates. Android requires JDK 17, an Android SDK and a debug keystore configured in Godot Editor Settings. This machine already has them under `D:/Godot/Android/`.

Android now uses a Gradle build for the native AdMob plugin. Run `tools/setup-android.ps1` once on this machine to extract the matching Godot Android source into `android/build/` and install SDK 36/build tools. This generated directory is ignored; the original Capacitor sources remain intact. Run `tools/build.ps1` for the complete checked export pipeline.

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . -- --self-test
godot --path . -- --gallery
godot --headless --path . --export-release 'Windows Desktop'
godot --headless --path . --export-debug Android
```

Create `exports/windows` and `exports/android` before exporting. Windows uses an embedded PCK. Android uses the existing application ID `com.vdsystem.putitback` and includes ARMv7, ARM64, and x86_64. The APK is a debug-signed installable build, not a Play Store release. A store release requires the owner's release signing key. An older installation signed with a different certificate cannot be upgraded directly.

`--self-test` runs 20 randomized solves per variant through actual hit testing and checks all timeout transitions. `--gallery` captures rendered screenshots in `verification/`. `--level=22` opens a specific practice level. Build outputs, screenshots, Godot caches, and Corel working sources are ignored by Git. The existing repository history and origin remote are retained. Version tags mark the pre-ad build (`v1.1.3`) and the ad integration (`v1.2.0`).

## Interstitial ads (Android)

Open `resources/ads_settings.tres` in the Godot Inspector to configure ads:

| Setting | Default | Behavior |
| --- | --- | --- |
| `enabled` | `true` | Master switch |
| `rounds_between_ads` | `10` | Completed rounds, including wins and timeouts |
| `minimum_gameplay_seconds` | `90.0` | Active puzzle time before the first ad and between ads |
| `show_in_practice` | `false` | Practice rounds neither count nor show ads by default |
| `test_ads` | `true` | Uses Google's dedicated test interstitial ID |
| `production_interstitial_id` | empty | Your Android interstitial unit ID |
| `general_audience_confirmed` | `false` | Explicit production gate; do not enable for a child-directed or mixed-age app |

Both frequency thresholds must be reached. Ads appear after the result animation, before the next puzzle. There are no ads mid-puzzle, at launch, or on Windows. Counters last for the app session and reset only after the SDK confirms an ad was shown. Loading is asynchronous: unavailable ads are skipped with no loading screen, with failed loads retried after 15–120 seconds. Loaded ads expire after 55 minutes. Dismissal or presentation failure resumes exactly one new round, with its full five-second timer, after the app regains focus.

The checked-in configuration serves **test ads only**. Production requires your AdMob Android app ID in Project Settings → AdMob → General → Android → App ID, your interstitial unit ID above, `test_ads = false`, and confirmation that the app is intended for a general audience. Invalid/demo production IDs or an unconfirmed audience disable live ads. Children/mixed-age distribution requires a separate audience and ad-request configuration review before enabling production.

For live ads, configure and publish the applicable privacy messages for your app in AdMob. The integration updates Google UMP consent information each launch and requests a required form at the menu or between rounds. It requests ads only when consent status permits it. Consent errors leave ads disabled for that launch. A **Privacy options** entry appears on the main menu when UMP requires it; changing consent discards the preloaded ad and reevaluates permission. The Google demo-app test configuration bypasses UMP because it cannot use your publisher's privacy messages. UMP's native dialog and third-party ad creative use their own typography; the game's UI, including its privacy entry, continues to use Cooper without outlines.

`scripts/ads/ad_tests.gd` runs as part of `--self-test` and covers frequency gates, practice exclusion, no inventory, failed presentation, duplicate callbacks, production configuration gates, and game pause/resume across focus changes using a fake provider. These tests do not validate Google's network or native UI. On an Android device, verify a test ad appears after the thresholds, closing it starts a full round, backgrounding preserves the timer, and airplane mode does not block play. With your own registered test device/app, also test UMP's required-consent and privacy-options flows before enabling live traffic.

Dependency: [Poing Studios Godot AdMob v5.0.0](https://github.com/poingstudios/godot-admob-plugin/releases/tag/v5.0.0), with the official Godot 4.7.2 Android `ads` binaries, vendored under `addons/admob` with MIT license headers. Other mediation SDKs are not included. One local patch makes its headless installer respect disabled platforms, avoiding an unnecessary iOS download. Release ZIP SHA-256 hashes: GDScript `93e9aaa8422b00f783c6b8c06a9e2ae3a81db071515517bb061bbb2d202d5fdf`; Android template `0d504a40b92db1abfdf839724c3a962a56569def93dbc608c9537fa38710e65a`.

## Aesthetic revision (1.2.1)

Scenes with three movable objects have exactly one misplaced object. Offsets are restrained, dragging uses only a soft shadow, and the park has one bush slightly off its circle. Brick segments remain aligned with one horizontally mirrored segment to fix. Bathroom red tiles follow the original orange floor grid in a checker pattern, avoid fixtures, and have one slightly shifted tile. Cooper lettering uses deep teal and warm ivory, with opaque caption surfaces for consistent contrast and no font outlines.

The self-test includes randomized checks for these layout rules. Gallery output includes dragging previews and restored brick/bathroom layouts.
