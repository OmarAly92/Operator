# Glass lab baseline

Run: `20260930-082046`. Native iOS 27 (iPhone 17 Pro simulator) against Operator's Flutter glass (the run used the example app; `lab.py summary` names the target since 2A.1).

| Status | Count |
|---|---|
| pass | 2 |
| fail | 44 |
| missing | 2 |
| reference | 0 |
| error | 0 |

| Scene | Case | Title | Status | Failing measures |
|---|---|---|---|---|
| material.regular | dark-black | Regular glass at three sizes | fail | ready.rim_rms 8.26 > 6.00, settled.rim_rms 8.26 > 6.00 |
| material.regular | dark-photo | Regular glass at three sizes | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.centre_pt 5.50 > 1.00 |
| material.regular | dark-stripes | Regular glass at three sizes | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.regular | dark-text | Regular glass at three sizes | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.regular | dark-white | Regular glass at three sizes | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.regular | light-black | Regular glass at three sizes | fail | ready.rim_rms 17.70 > 6.00, settled.rim_rms 17.70 > 6.00 |
| material.regular | light-photo | Regular glass at three sizes | fail | ready.bbox_pt 7.00 > 1.00, settled.bbox_pt 7.00 > 1.00, ready.centre_pt 5.00 > 1.00 |
| material.regular | light-stripes | Regular glass at three sizes | fail | ready.bbox_pt 9.00 > 1.00, settled.bbox_pt 9.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.regular | light-text | Regular glass at three sizes | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.regular | light-white | Regular glass at three sizes | fail | ready.bbox_pt 10.00 > 1.00, settled.bbox_pt 10.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.tinted | dark-black | Tinted glass and a prominent button | fail | ready.rim_rms 49.08 > 6.00, settled.rim_rms 49.08 > 6.00, ready.bbox_pt 2.00 > 1.00 |
| material.tinted | dark-stripes | Tinted glass and a prominent button | fail | ready.bbox_pt 2.00 > 1.00, ready.centre_pt 2.00 > 1.00, settled.bbox_pt 2.00 > 1.00 |
| material.tinted | dark-white | Tinted glass and a prominent button | fail | ready.rim_rms 18.64 > 6.00, settled.rim_rms 18.64 > 6.00, ready.bbox_pt 2.00 > 1.00 |
| material.tinted | light-black | Tinted glass and a prominent button | fail | ready.rim_rms 39.30 > 6.00, settled.rim_rms 39.30 > 6.00, ready.bbox_pt 3.00 > 1.00 |
| material.tinted | light-stripes | Tinted glass and a prominent button | fail | ready.bbox_pt 2.00 > 1.00, ready.centre_pt 2.00 > 1.00, settled.bbox_pt 2.00 > 1.00 |
| material.tinted | light-white | Tinted glass and a prominent button | fail | ready.rim_rms 21.48 > 6.00, settled.rim_rms 21.48 > 6.00, ready.bbox_pt 2.00 > 1.00 |
| material.clear | dark-photo | Clear glass with and without the dimming layer | fail | ready.bbox_pt 9.00 > 1.00, settled.bbox_pt 9.00 > 1.00, ready.centre_pt 4.50 > 1.00 |
| material.clear | dark-white | Clear glass with and without the dimming layer | fail | ready.bbox_pt 9.00 > 1.00, settled.bbox_pt 9.00 > 1.00, ready.centre_pt 4.50 > 1.00 |
| material.clear | light-photo | Clear glass with and without the dimming layer | fail | ready.bbox_pt 6.00 > 1.00, settled.bbox_pt 6.00 > 1.00, ready.rim_rms 19.63 > 6.00 |
| material.clear | light-white | Clear glass with and without the dimming layer | fail | ready.bbox_pt 6.00 > 1.00, settled.bbox_pt 6.00 > 1.00, ready.centre_pt 2.50 > 1.00 |
| material.interactive | dark-photo | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.bbox_pt 3.00 > 1.00, settled.bbox_pt 3.00 > 1.00 |
| material.interactive | dark-stripes | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1 |
| material.interactive | light-photo | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.luminance 12.84 > 3.00, settled.luminance 12.84 > 3.00 |
| material.interactive | light-stripes | Interactive glass press and drag | fail | motion.events.native_motion 0 < 1, ready.luminance 6.59 > 3.00, settled.luminance 6.59 > 3.00 |
| material.flip | dark-scroll | Small and large glass over content that turns white then black | fail | motion.event0.cy.overshoot_pct 661.38 > 2.00, motion.event4.height.response_pct 70.83 > 5.00, motion.event4.cy.response_pct 70.83 > 5.00 |
| material.flip | light-scroll | Small and large glass over content that turns white then black | fail | motion.event1.height.overshoot_pct 386.79 > 2.00, motion.event3.height.overshoot_pct 175.00 > 2.00, motion.event0.cy.peak_ms 908.33 > 17.00 |
| material.shapes | dark-stripes | Capsule, fixed radius and concentric shapes | fail | ready.bbox_pt 12.00 > 1.00, settled.bbox_pt 12.00 > 1.00, ready.centre_pt 6.00 > 1.00 |
| material.shapes | light-stripes | Capsule, fixed radius and concentric shapes | fail | ready.bbox_pt 9.00 > 1.00, settled.bbox_pt 9.00 > 1.00, ready.centre_pt 4.50 > 1.00 |
| material.morph | dark-photo | Button morphs into a badge stack | fail | motion.events.count 5 > 0 |
| material.union | light-stripes | Glass union of four items in two groups | fail | ready.rim_rms 33.79 > 6.00, settled.rim_rms 33.79 > 6.00, ready.bbox_pt 4.00 > 1.00 |
| material.edge.soft | dark-scroll | Soft scroll edge effect under an inline bar | fail | ready.mad 21.27 > 4.00, settled.mad 21.27 > 4.00 |
| material.materialize | light-photo | Glass materializes in and out | fail | motion.events.count 4 > 0, settled.rim_rms 19.80 > 6.00, ready.rim_rms 19.77 > 6.00 |
| material.morph | light-photo | Button morphs into a badge stack | fail | motion.events.count 4 > 0, ready.bbox_pt 3.00 > 1.00, settled.bbox_pt 3.00 > 1.00 |
| material.materialize | dark-photo | Glass materializes in and out | fail | motion.events.count 4 > 0, ready.bbox_pt 3.00 > 1.00, settled.bbox_pt 3.00 > 1.00 |
| material.merge | dark-stripes | Two circles merge and split in a container | fail | motion.events.count 4 > 0, ready.mad 8.59 > 4.00, settled.mad 8.59 > 4.00 |
| material.materialize | light-stripes | Glass materializes in and out | fail | motion.events.count 4 > 0, ready.bbox_pt 2.00 > 1.00, settled.bbox_pt 2.00 > 1.00 |
| material.materialize | dark-stripes | Glass materializes in and out | fail | motion.events.count 4 > 0, ready.mad 5.30 > 4.00, settled.mad 5.30 > 4.00 |
| material.morph | light-stripes | Button morphs into a badge stack | fail | ready.bbox_pt 4.00 > 1.00, settled.bbox_pt 4.00 > 1.00, motion.events.count 3 > 0 |
| material.union | dark-stripes | Glass union of four items in two groups | fail | ready.bbox_pt 4.00 > 1.00, settled.bbox_pt 4.00 > 1.00, ready.mad 12.22 > 4.00 |
| material.merge | light-stripes | Two circles merge and split in a container | fail | motion.events.count 3 > 0, ready.mad 8.60 > 4.00, settled.mad 8.60 > 4.00 |
| material.morph | dark-stripes | Button morphs into a badge stack | fail | motion.events.count 3 > 0, ready.rim_rms 6.62 > 6.00, settled.rim_rms 6.61 > 6.00 |
| material.edge.soft | light-scroll | Soft scroll edge effect under an inline bar | fail | ready.mad 5.67 > 4.00, settled.mad 5.67 > 4.00 |
| material.edge.automatic | dark-scroll | Automatic scroll edge effect under an inline bar | fail | ready.mad 4.56 > 4.00, settled.mad 4.56 > 4.00 |
| material.edge.hard | dark-scroll | Hard scroll edge effect under an inline bar | fail | ready.mad 4.56 > 4.00, settled.mad 4.56 > 4.00 |
| material.edge.automatic | light-scroll | Automatic scroll edge effect under an inline bar | pass | — |
| material.edge.hard | light-scroll | Hard scroll edge effect under an inline bar | pass | — |
| material.content | dark-photo | Content layer materials | missing | — |
| material.content | light-photo | Content layer materials | missing | — |
