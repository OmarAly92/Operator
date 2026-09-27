# Glass lab baseline

Run: `20260927-035111`. Native iOS 27 (iPhone 17 Pro simulator) against Operator's Flutter glass.

| Status | Count |
|---|---|
| pass | 0 |
| fail | 96 |
| missing | 120 |
| reference | 12 |
| error | 0 |

| Scene | Case | Title | Status | Failing measures |
|---|---|---|---|---|
| tabbar.rest | dark-black | Tab bar with a search tab | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.mad 24.86 > 4.00 |
| tabbar.rest | dark-black-increase-contrast | Tab bar with a search tab | fail | ready.mad 18.32 > 4.00, settled.mad 18.32 > 4.00, ready.rim_rms 12.77 > 6.00 |
| tabbar.rest | dark-black-reduce-motion | Tab bar with a search tab | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.mad 24.86 > 4.00 |
| tabbar.rest | dark-black-reduce-transparency | Tab bar with a search tab | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.mad 20.53 > 4.00 |
| tabbar.rest | dark-photo | Tab bar with a search tab | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.mad 19.70 > 4.00 |
| tabbar.rest | dark-photo-increase-contrast | Tab bar with a search tab | fail | ready.mad 40.88 > 4.00, settled.mad 40.88 > 4.00, ready.luminance 27.52 > 3.00 |
| tabbar.rest | dark-photo-reduce-motion | Tab bar with a search tab | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.mad 19.79 > 4.00 |
| tabbar.rest | dark-photo-reduce-transparency | Tab bar with a search tab | fail | ready.mad 66.79 > 4.00, settled.mad 66.79 > 4.00, ready.luminance 47.00 > 3.00 |
| tabbar.rest | dark-stripes | Tab bar with a search tab | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.mad 17.26 > 4.00 |
| tabbar.rest | dark-stripes-increase-contrast | Tab bar with a search tab | fail | ready.luminance 49.49 > 3.00, settled.luminance 49.49 > 3.00, ready.mad 54.84 > 4.00 |
| tabbar.rest | dark-stripes-reduce-motion | Tab bar with a search tab | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.mad 17.26 > 4.00 |
| tabbar.rest | dark-stripes-reduce-transparency | Tab bar with a search tab | fail | ready.luminance 82.51 > 3.00, settled.luminance 82.51 > 3.00, ready.mad 82.97 > 4.00 |
| tabbar.rest | dark-white | Tab bar with a search tab | fail | ready.luminance 40.67 > 3.00, settled.luminance 40.67 > 3.00, ready.mad 47.37 > 4.00 |
| tabbar.rest | dark-white-increase-contrast | Tab bar with a search tab | fail | ready.luminance 84.99 > 3.00, settled.luminance 84.99 > 3.00, ready.mad 93.26 > 4.00 |
| tabbar.rest | dark-white-reduce-motion | Tab bar with a search tab | fail | ready.luminance 40.67 > 3.00, settled.luminance 40.67 > 3.00, ready.mad 47.37 > 4.00 |
| tabbar.rest | dark-white-reduce-transparency | Tab bar with a search tab | fail | ready.luminance 139.05 > 3.00, settled.luminance 139.05 > 3.00, ready.mad 144.47 > 4.00 |
| tabbar.rest | light-black | Tab bar with a search tab | fail | ready.mad 19.08 > 4.00, settled.mad 19.08 > 4.00, ready.luminance 13.93 > 3.00 |
| tabbar.rest | light-photo | Tab bar with a search tab | fail | ready.bbox_pt 4.00 > 1.00, settled.bbox_pt 4.00 > 1.00, ready.mad 12.47 > 4.00 |
| tabbar.rest | light-stripes | Tab bar with a search tab | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.mad 14.27 > 4.00 |
| tabbar.rest | light-white | Tab bar with a search tab | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.centre_pt 3.00 > 1.00 |
| tabbar.press | dark-stripes | Tab bar press and hold | fail | motion.event1.width.overshoot_pct 553.32 > 2.00, motion.event0.width.overshoot_pct 277.58 > 2.00, motion.event1.width.settle_ms 208.33 > 17.00 |
| tabbar.press | light-stripes | Tab bar press and hold | fail | motion.event1.luma.peak_ms 375.00 > 17.00, motion.event1.luma.settle_ms 266.67 > 17.00, motion.event1.width.response_pct 74.19 > 5.00 |
| tabbar.drag | dark-stripes | Tab selection lens dragged across tabs | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, motion.event0.cx.overshoot_pct 19.11 > 2.00 |
| tabbar.drag | dark-stripes-increase-contrast | Tab selection lens dragged across tabs | fail | ready.luminance 39.73 > 3.00, settled.luminance 38.83 > 3.00, ready.mad 44.72 > 4.00 |
| tabbar.drag | dark-stripes-reduce-motion | Tab selection lens dragged across tabs | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, settled.mad 17.81 > 4.00 |
| tabbar.drag | dark-stripes-reduce-transparency | Tab selection lens dragged across tabs | fail | motion.event0.width.overshoot_pct 280.00 > 5.36, ready.luminance 66.46 > 3.00, settled.luminance 65.88 > 3.00 |
| tabbar.drag | light-stripes | Tab selection lens dragged across tabs | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.mad 12.07 > 4.00 |
| button.press | dark-stripes | Glass and prominent button press | fail | motion.event2.width.response_pct 60.71 > 5.00, motion.event2.width.damping 0.41 > 0.05, ready.bbox_pt 5.00 > 1.00 |
| button.press | light-stripes | Glass and prominent button press | fail | motion.event2.width.response_pct 76.19 > 5.00, motion.event3.width.settle_ms 250.00 > 17.00, motion.event3.width.response_pct 64.71 > 5.00 |
| sheet.detents | dark-photo | Sheet moved between its detents | fail | settled.bbox_pt 712.00 > 1.00, settled.centre_pt 356.00 > 1.00, settled.luminance 65.07 > 3.00 |
| sheet.detents | dark-photo-increase-contrast | Sheet moved between its detents | fail | settled.bbox_pt 712.00 > 1.00, settled.centre_pt 356.00 > 1.00, settled.luminance 54.28 > 3.00 |
| sheet.detents | dark-photo-reduce-motion | Sheet moved between its detents | fail | settled.bbox_pt 712.00 > 1.00, settled.centre_pt 356.00 > 1.00, settled.luminance 65.14 > 3.00 |
| sheet.detents | dark-photo-reduce-transparency | Sheet moved between its detents | fail | settled.bbox_pt 712.00 > 1.00, settled.centre_pt 356.00 > 1.00, settled.luminance 51.76 > 3.00 |
| sheet.detents | dark-stripes | Sheet moved between its detents | fail | settled.bbox_pt 710.00 > 1.00, settled.centre_pt 355.00 > 1.00, settled.luminance 92.42 > 3.00 |
| sheet.detents | dark-stripes-increase-contrast | Sheet moved between its detents | fail | settled.bbox_pt 710.00 > 1.00, settled.centre_pt 355.00 > 1.00, settled.luminance 79.19 > 3.00 |
| sheet.detents | dark-stripes-reduce-motion | Sheet moved between its detents | fail | settled.bbox_pt 710.00 > 1.00, settled.centre_pt 355.00 > 1.00, settled.luminance 92.44 > 3.00 |
| sheet.detents | dark-stripes-reduce-transparency | Sheet moved between its detents | fail | settled.bbox_pt 710.00 > 1.00, settled.centre_pt 355.00 > 1.00, settled.luminance 76.33 > 3.00 |
| sheet.detents | light-photo | Sheet moved between its detents | fail | settled.bbox_pt 717.00 > 1.00, settled.centre_pt 358.50 > 1.00, settled.rim_rms 119.57 > 6.00 |
| sheet.detents | light-stripes | Sheet moved between its detents | fail | settled.bbox_pt 714.00 > 1.00, settled.centre_pt 357.00 > 1.00, settled.mad 63.00 > 4.00 |
| navbar.inline | dark-black | Inline title, back button and trailing group | fail | ready.bbox_pt 7.00 > 1.00, settled.bbox_pt 7.00 > 1.00, ready.rim_rms 27.50 > 6.00 |
| navbar.inline | dark-stripes | Inline title, back button and trailing group | fail | ready.bbox_pt 6.00 > 1.00, settled.bbox_pt 6.00 > 1.00, ready.rim_rms 16.37 > 6.00 |
| navbar.inline | dark-white | Inline title, back button and trailing group | fail | ready.rim_rms 41.15 > 6.00, settled.rim_rms 41.15 > 6.00, ready.bbox_pt 6.00 > 1.00 |
| navbar.inline | light-black | Inline title, back button and trailing group | fail | ready.rim_rms 96.06 > 6.00, settled.rim_rms 96.06 > 6.00, ready.bbox_pt 6.00 > 1.00 |
| navbar.inline | light-stripes | Inline title, back button and trailing group | fail | ready.bbox_pt 11.00 > 1.00, settled.bbox_pt 11.00 > 1.00, ready.rim_rms 58.81 > 6.00 |
| navbar.inline | light-white | Inline title, back button and trailing group | fail | ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00, ready.rim_rms 44.80 > 6.00 |
| material.regular | dark-black | Regular glass at three sizes | fail | ready.luminance 10.48 > 3.00, settled.luminance 10.48 > 3.00, ready.rim_rms 16.26 > 6.00 |
| material.regular | dark-black-increase-contrast | Regular glass at three sizes | fail | ready.rim_rms 9.77 > 6.00, settled.rim_rms 9.77 > 6.00 |
| material.regular | dark-black-reduce-motion | Regular glass at three sizes | fail | ready.luminance 10.48 > 3.00, settled.luminance 10.48 > 3.00, ready.rim_rms 16.26 > 6.00 |
| material.regular | dark-black-reduce-transparency | Regular glass at three sizes | fail | ready.rim_rms 10.44 > 6.00, settled.rim_rms 10.44 > 6.00, ready.luminance 4.34 > 3.00 |
| material.regular | dark-photo | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.centre_pt 7.00 > 1.00 |
| material.regular | dark-photo-increase-contrast | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.centre_pt 7.00 > 1.00 |
| material.regular | dark-photo-reduce-motion | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.centre_pt 7.00 > 1.00 |
| material.regular | dark-photo-reduce-transparency | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.luminance 30.69 > 3.00 |
| material.regular | dark-stripes | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-stripes-increase-contrast | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-stripes-reduce-motion | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-stripes-reduce-transparency | Regular glass at three sizes | fail | ready.luminance 49.97 > 3.00, settled.luminance 49.97 > 3.00, ready.bbox_pt 14.00 > 1.00 |
| material.regular | dark-text | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-text-increase-contrast | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-text-reduce-motion | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.00 > 1.00 |
| material.regular | dark-text-reduce-transparency | Regular glass at three sizes | fail | ready.luminance 69.83 > 3.00, settled.luminance 69.83 > 3.00, ready.mad 71.41 > 4.00 |
| material.regular | dark-white | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.luminance 27.92 > 3.00 |
| material.regular | dark-white-increase-contrast | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.luminance 28.32 > 3.00 |
| material.regular | dark-white-reduce-motion | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.luminance 27.92 > 3.00 |
| material.regular | dark-white-reduce-transparency | Regular glass at three sizes | fail | ready.luminance 79.61 > 3.00, settled.luminance 79.61 > 3.00, ready.mad 81.33 > 4.00 |
| material.regular | light-black | Regular glass at three sizes | fail | ready.rim_rms 26.52 > 6.00, settled.rim_rms 26.52 > 6.00, ready.luminance 11.93 > 3.00 |
| material.regular | light-photo | Regular glass at three sizes | fail | ready.bbox_pt 15.00 > 1.00, settled.bbox_pt 15.00 > 1.00, ready.centre_pt 8.50 > 1.00 |
| material.regular | light-stripes | Regular glass at three sizes | fail | ready.bbox_pt 14.00 > 1.00, settled.bbox_pt 14.00 > 1.00, ready.centre_pt 8.50 > 1.00 |
| material.regular | light-text | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.centre_pt 8.50 > 1.00 |
| material.regular | light-white | Regular glass at three sizes | fail | ready.bbox_pt 13.00 > 1.00, settled.bbox_pt 13.00 > 1.00, ready.centre_pt 8.50 > 1.00 |
| material.tinted | dark-black | Tinted glass and a prominent button | fail | ready.rim_rms 28.43 > 6.00, settled.rim_rms 28.43 > 6.00, ready.luminance 8.32 > 3.00 |
| material.tinted | dark-stripes | Tinted glass and a prominent button | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.centre_pt 4.50 > 1.00 |
| material.tinted | dark-white | Tinted glass and a prominent button | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.centre_pt 4.50 > 1.00 |
| material.tinted | light-black | Tinted glass and a prominent button | fail | ready.rim_rms 22.77 > 6.00, settled.rim_rms 22.77 > 6.00, ready.mad 6.09 > 4.00 |
| material.tinted | light-stripes | Tinted glass and a prominent button | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.mad 9.26 > 4.00 |
| material.tinted | light-white | Tinted glass and a prominent button | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.mad 15.40 > 4.00 |
| material.clear | dark-photo | Clear glass with and without the dimming layer | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.luminance 18.80 > 3.00 |
| material.clear | dark-white | Clear glass with and without the dimming layer | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.luminance 23.39 > 3.00 |
| material.clear | light-photo | Clear glass with and without the dimming layer | fail | ready.bbox_pt 15.00 > 1.00, settled.bbox_pt 15.00 > 1.00, ready.rim_rms 24.32 > 6.00 |
| material.clear | light-white | Clear glass with and without the dimming layer | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.luminance 16.30 > 3.00 |
| material.interactive | dark-photo | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.bbox_pt 8.00 > 1.00, settled.bbox_pt 8.00 > 1.00 |
| material.interactive | dark-stripes | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00 |
| material.interactive | light-photo | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00 |
| material.interactive | light-stripes | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00 |
| material.edge.hard | light-scroll | Hard scroll edge effect under an inline bar | fail | ready.bbox_pt ∞ > 1.00, ready.centre_pt ∞ > 1.00, motion.event0.cy.overshoot_pct 256.36 > 2.00 |
| material.edge.automatic | light-scroll | Automatic scroll edge effect under an inline bar | fail | ready.bbox_pt ∞ > 1.00, ready.centre_pt ∞ > 1.00, motion.event0.cy.overshoot_pct 254.01 > 2.00 |
| material.edge.soft | light-scroll | Soft scroll edge effect under an inline bar | fail | ready.bbox_pt ∞ > 1.00, ready.centre_pt ∞ > 1.00, ready.rim_rms 134.53 > 6.00 |
| button.styles | dark-black | Glass button styles, sizes and shapes | fail | ready.bbox_pt 53.00 > 1.00, settled.bbox_pt 53.00 > 1.00, ready.rim_rms 104.91 > 6.00 |
| button.styles | light-black | Glass button styles, sizes and shapes | fail | ready.bbox_pt 52.00 > 1.00, settled.bbox_pt 52.00 > 1.00, ready.rim_rms 92.19 > 6.00 |
| button.styles | dark-stripes | Glass button styles, sizes and shapes | fail | ready.bbox_pt 49.00 > 1.00, settled.bbox_pt 49.00 > 1.00, ready.mad 19.79 > 4.00 |
| button.styles | dark-white | Glass button styles, sizes and shapes | fail | ready.bbox_pt 48.00 > 1.00, settled.bbox_pt 48.00 > 1.00, ready.centre_pt 38.00 > 1.00 |
| button.styles | light-stripes | Glass button styles, sizes and shapes | fail | ready.bbox_pt 44.00 > 1.00, settled.bbox_pt 44.00 > 1.00, ready.mad 25.12 > 4.00 |
| button.styles | light-white | Glass button styles, sizes and shapes | fail | ready.bbox_pt 43.00 > 1.00, settled.bbox_pt 43.00 > 1.00, ready.centre_pt 14.00 > 1.00 |
| material.edge.soft | dark-scroll | Soft scroll edge effect under an inline bar | fail | ready.mad 56.21 > 4.00, motion.event0.height.overshoot_pct 27.27 > 2.00, ready.rim_rms 79.78 > 6.00 |
| material.edge.automatic | dark-scroll | Automatic scroll edge effect under an inline bar | fail | ready.mad 56.21 > 4.00, ready.rim_rms 79.78 > 6.00, settled.mad 50.64 > 4.00 |
| material.edge.hard | dark-scroll | Hard scroll edge effect under an inline bar | fail | ready.mad 55.16 > 4.00, ready.rim_rms 76.39 > 6.00, settled.mad 50.64 > 4.00 |
| alert.three | dark-stripes | Alert with three actions | missing | — |
| alert.three | dark-white | Alert with three actions | missing | — |
| alert.three | light-stripes | Alert with three actions | missing | — |
| alert.three | light-white | Alert with three actions | missing | — |
| alert.two | dark-stripes | Alert with two actions | missing | — |
| alert.two | dark-white | Alert with two actions | missing | — |
| alert.two | light-stripes | Alert with two actions | missing | — |
| alert.two | light-white | Alert with two actions | missing | — |
| confirm.source | dark-stripes | Confirmation dialog anchored to its button | missing | — |
| confirm.source | light-stripes | Confirmation dialog anchored to its button | missing | — |
| contextmenu.card | dark-stripes | Context menu on a card | missing | — |
| contextmenu.card | light-stripes | Context menu on a card | missing | — |
| datepicker.compact | dark-white | Compact date picker | missing | — |
| datepicker.compact | light-white | Compact date picker | missing | — |
| datepicker.inline | dark-white | Inline date picker | missing | — |
| datepicker.inline | light-white | Inline date picker | missing | — |
| datepicker.wheel | dark-white | Wheel date picker | missing | — |
| datepicker.wheel | light-white | Wheel date picker | missing | — |
| list.form | dark-none | Inset grouped form | missing | — |
| list.form | light-none | Inset grouped form | missing | — |
| material.content | dark-photo | Content layer materials | missing | — |
| material.content | light-photo | Content layer materials | missing | — |
| material.flip | dark-scroll | Small and large glass over content that turns white then black | missing | — |
| material.flip | light-scroll | Small and large glass over content that turns white then black | missing | — |
| material.materialize | dark-photo | Glass materializes in and out | missing | — |
| material.materialize | dark-stripes | Glass materializes in and out | missing | — |
| material.materialize | light-photo | Glass materializes in and out | missing | — |
| material.materialize | light-stripes | Glass materializes in and out | missing | — |
| material.merge | dark-stripes | Two circles merge and split in a container | missing | — |
| material.merge | light-stripes | Two circles merge and split in a container | missing | — |
| material.morph | dark-photo | Button morphs into a badge stack | missing | — |
| material.morph | dark-stripes | Button morphs into a badge stack | missing | — |
| material.morph | light-photo | Button morphs into a badge stack | missing | — |
| material.morph | light-stripes | Button morphs into a badge stack | missing | — |
| material.shapes | dark-stripes | Capsule, fixed radius and concentric shapes | missing | — |
| material.shapes | light-stripes | Capsule, fixed radius and concentric shapes | missing | — |
| material.union | dark-stripes | Glass union of four items in two groups | missing | — |
| material.union | light-stripes | Glass union of four items in two groups | missing | — |
| menu.bar | dark-photo | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-increase-contrast | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-reduce-motion | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-reduce-transparency | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-increase-contrast | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-reduce-motion | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-reduce-transparency | Menu from a toolbar button | missing | — |
| menu.bar | light-photo | Menu from a toolbar button | missing | — |
| menu.bar | light-stripes | Menu from a toolbar button | missing | — |
| menu.pressdrag | dark-stripes | Press the menu button and drag onto an item | missing | — |
| menu.pressdrag | light-stripes | Press the menu button and drag onto an item | missing | — |
| menu.submenu | dark-stripes | Menu with a submenu | missing | — |
| menu.submenu | light-stripes | Menu with a submenu | missing | — |
| navbar.badge | dark-stripes | Badge on a bar button | missing | — |
| navbar.badge | light-stripes | Badge on a bar button | missing | — |
| navbar.groups | dark-stripes | Toolbar groups, spacer and prominent action | missing | — |
| navbar.groups | light-stripes | Toolbar groups, spacer and prominent action | missing | — |
| navbar.large | dark-scroll | Large title with subtitle scrolling under the bar | missing | — |
| navbar.large | light-scroll | Large title with subtitle scrolling under the bar | missing | — |
| navbar.minimize | dark-scroll | Navigation bar minimizes on scroll | missing | — |
| navbar.minimize | light-scroll | Navigation bar minimizes on scroll | missing | — |
| navbar.push | dark-stripes | Toolbar items across push and pop | missing | — |
| navbar.push | light-stripes | Toolbar items across push and pop | missing | — |
| pagecontrol | dark-photo | Page control with a platter | missing | — |
| pagecontrol | light-photo | Page control with a platter | missing | — |
| picker.menu | dark-white | Menu picker | missing | — |
| picker.menu | light-white | Menu picker | missing | — |
| popover.bar | dark-stripes | Popover from a bar button | missing | — |
| popover.bar | light-stripes | Popover from a bar button | missing | — |
| progress | dark-white | Progress views and a thumbless slider | missing | — |
| progress | light-white | Progress views and a thumbless slider | missing | — |
| push.zoom | dark-stripes | Push with a zoom transition from a card | missing | — |
| push.zoom | light-stripes | Push with a zoom transition from a card | missing | — |
| search.bottom | dark-photo | Bottom search field above the keyboard | missing | — |
| search.bottom | light-photo | Bottom search field above the keyboard | missing | — |
| search.minimized | dark-photo | Minimized search button | missing | — |
| search.minimized | light-photo | Minimized search button | missing | — |
| search.scopes | dark-white | Search scopes | missing | — |
| search.scopes | light-white | Search scopes | missing | — |
| segmented | dark-stripes | Segmented control tapped, then dragged | missing | — |
| segmented | dark-white | Segmented control tapped, then dragged | missing | — |
| segmented | light-stripes | Segmented control tapped, then dragged | missing | — |
| segmented | light-white | Segmented control tapped, then dragged | missing | — |
| sheet.crossfade | dark-stripes | Cross-fade sheet presentation | missing | — |
| sheet.crossfade | light-stripes | Cross-fade sheet presentation | missing | — |
| sheet.scroll | dark-stripes | Large sheet with scrolling content | missing | — |
| sheet.scroll | light-stripes | Large sheet with scrolling content | missing | — |
| sheet.zoom | dark-stripes | Sheet zooms out of a toolbar button | missing | — |
| sheet.zoom | light-stripes | Sheet zooms out of a toolbar button | missing | — |
| slider | dark-stripes | Slider flicked, then dragged slowly | missing | — |
| slider | dark-white | Slider flicked, then dragged slowly | missing | — |
| slider | light-stripes | Slider flicked, then dragged slowly | missing | — |
| slider | light-white | Slider flicked, then dragged slowly | missing | — |
| stepper | dark-white | Stepper | missing | — |
| stepper | light-white | Stepper | missing | — |
| swipe.row | dark-none | Swipe actions on a row | missing | — |
| swipe.row | light-none | Swipe actions on a row | missing | — |
| tabbar.accessory | dark-scroll | Tab bar bottom accessory, expanded then inline | missing | — |
| tabbar.accessory | light-scroll | Tab bar bottom accessory, expanded then inline | missing | — |
| tabbar.badge | dark-stripes | Tab badge | missing | — |
| tabbar.badge | light-stripes | Tab badge | missing | — |
| tabbar.minimize | dark-scroll | Tab bar minimizes on scroll | missing | — |
| tabbar.minimize | light-scroll | Tab bar minimizes on scroll | missing | — |
| tabbar.prominent | dark-stripes | Prominent tab | missing | — |
| tabbar.prominent | light-stripes | Prominent tab | missing | — |
| tabbar.search | dark-photo | Search tab morphs into a field | missing | — |
| tabbar.search | light-photo | Search tab morphs into a field | missing | — |
| textfield | dark-black | Text and search fields | missing | — |
| textfield | dark-white | Text and search fields | missing | — |
| textfield | light-black | Text and search fields | missing | — |
| textfield | light-white | Text and search fields | missing | — |
| toggle | dark-black | Switch tapped, then its knob dragged | missing | — |
| toggle | dark-stripes | Switch tapped, then its knob dragged | missing | — |
| toggle | dark-white | Switch tapped, then its knob dragged | missing | — |
| toggle | light-black | Switch tapped, then its knob dragged | missing | — |
| toggle | light-stripes | Switch tapped, then its knob dragged | missing | — |
| toggle | light-white | Switch tapped, then its knob dragged | missing | — |
| toolbar.bottom | dark-photo | Bottom toolbar with groups | missing | — |
| toolbar.bottom | dark-stripes | Bottom toolbar with groups | missing | — |
| toolbar.bottom | light-photo | Bottom toolbar with groups | missing | — |
| toolbar.bottom | light-stripes | Bottom toolbar with groups | missing | — |
| apple.calendar.toolbar | dark-none | Calendar grouped toolbar and bottom bar | reference | — |
| apple.calendar.toolbar | light-none | Calendar grouped toolbar and bottom bar | reference | — |
| apple.maps.sheet | dark-none | Maps sheet dragged to full, then to its smallest detent | reference | — |
| apple.maps.sheet | light-none | Maps sheet dragged to full, then to its smallest detent | reference | — |
| apple.photos.scroll | dark-none | Photos grid scrolled under the tab bar | reference | — |
| apple.photos.scroll | light-none | Photos grid scrolled under the tab bar | reference | — |
| apple.photos.search | dark-none | Photos search tab | reference | — |
| apple.photos.search | light-none | Photos search tab | reference | — |
| apple.reminders.menu | dark-none | Reminders list menu | reference | — |
| apple.reminders.menu | light-none | Reminders list menu | reference | — |
| apple.settings.large | dark-none | Settings large title under the bar | reference | — |
| apple.settings.large | light-none | Settings large title under the bar | reference | — |
