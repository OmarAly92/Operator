# Glass lab baseline

Run: `20261002-200447`. Native iOS 27 (iPhone 17 Pro simulator) against the ios_liquid_glass example app.

| Status | Count |
|---|---|
| pass | 8 |
| fail | 2 |
| missing | 0 |
| reference | 0 |
| error | 0 |

| Scene | Case | Title | Status | Failing measures |
|---|---|---|---|---|
| material.regular | dark-black | Regular glass at three sizes | pass | — |
| material.regular | dark-photo | Regular glass at three sizes | pass | — |
| material.regular | dark-stripes | Regular glass at three sizes | pass | — |
| material.regular | dark-text | Regular glass at three sizes | fail | ready.rim_rms 10.18 > 6.00, settled.rim_rms 10.18 > 6.00 |
| material.regular | dark-white | Regular glass at three sizes | pass | — |
| material.regular | light-black | Regular glass at three sizes | pass | — |
| material.regular | light-photo | Regular glass at three sizes | fail | ready.bbox_pt 2.00 > 1.00, settled.bbox_pt 2.00 > 1.00 |
| material.regular | light-stripes | Regular glass at three sizes | pass | — |
| material.regular | light-text | Regular glass at three sizes | pass | — |
| material.regular | light-white | Regular glass at three sizes | pass | — |
