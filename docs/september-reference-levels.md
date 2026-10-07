# September 29 level references

Implemented on September 30, 2026, using files from `Downloads/Pot it back` and `Downloads/Background Level10.zip`.

| Source | Level | Implementation |
| --- | --- | --- |
| `viber_image_2026-09-29_15-21-56-187.jpg` | 25, drawers | Correct overlap ordering: upper drawer fronts cover lower drawers. Alpha hit testing respects the visible surface. |
| `viber_image_2026-09-29_15-21-57-266.jpg` and `Background Level10.zip` | 10, pencils | Use the new background and move the pencil row down by the same 950 artwork pixels. |
| `viber_image_2026-09-29_15-21-57-393.jpg` | 2, elevator | Center buttons on the circles in the background; use consistent button size. |
| `viber_image_2026-09-29_15-30-27-557.png` | 15, brick arch | Reproduce the solved right-hand arch using the original brick sprite; displace an upper course horizontally as the fault. |
| `viber_image_2026-09-29_15-39-44-297.png` | 19, hexagons | Full-screen cream/blue/red flower pattern. One red center trades places with a cream tile two rows below, as in the comparison. |
| `viber_image_2026-09-29_15-46-24-953.jpg` | 26, dessert picture | A 4 by 8 picture grid with one or two exchanged pairs. Drag onto another tile to exchange positions. |

The first three screenshots have no written annotations. Their changes address the visible overlap/alignment issues, with the replacement pencil background establishing the intended lower tray position.

No separate dessert artwork archive was present in Downloads. `assets/new/DessertTable_Reference.jpg` retains the supplied 921 by 880 JPEG unchanged. Godot `AtlasTexture` regions use its solved right-hand panel (x=476, y=13, width=429, height=856). This preserves the actual supplied artwork rather than recreating it. The panel has screenshot-level resolution; replace the source with a higher-resolution original if one becomes available.

All existing level IDs are occupied through 25, so the previously unnumbered missing scene uses ID 26. `scripts/reference_levels.gd` defines the new layouts. Tests cover arch-course repair, flower geometry, picture swaps and cancellation, drawer occlusion, and access to every level in the picker.
