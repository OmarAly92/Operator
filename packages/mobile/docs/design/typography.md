# Typography

Extracted from `docs/design/Operator Mobile - standalone.html` (a Pencil "bundled page"
export). The decoded template lives at the file's `<script type="__bundler/template">`
payload; embedded font binaries live in its `<script type="__bundler/manifest">` map.

## Anthropic Sans — cleared and wired

The prototype's `@font-face` rules declare three families: `JetBrains Mono`,
`Anthropic Sans Text`, and `Anthropic Sans Display`. Their embedded binaries were extracted
and inspected via `fontTools`' `name` table:

| Family | Copyright | Manufacturer | Designer | License |
|---|---|---|---|---|
| JetBrains Mono | Copyright 2020 The JetBrains Mono Project Authors | — | — | SIL OFL (safe to embed) |
| Anthropic Sans Text / Display | **Copyright 2025 Anthropic PBC** | BSPK LLC | BSPK x Geist x Anthropic | none declared |

**Anthropic Sans is Anthropic's own proprietary corporate typeface.** This was flagged to
the user as a licensing/trademark question rather than an engineering decision. The user
has since supplied cleared `.otf` files directly at
`assets/fonts/anthropic_sans/{AnthropicSansText,AnthropicSansDisplay}-<weight>[-Italic].otf`
(300/400/500/600/700/800, with italics for 400/500/700/800). Both families are now wired:

1. `pubspec.yaml` — `Anthropic Sans Text` and `Anthropic Sans Display` `fonts:` entries
   added, mirroring the JetBrains Mono entry's shape, one asset per weight/style.
2. `AppTextStyle._textStyle` sets `fontFamily: 'Anthropic Sans Text'` (used by every
   `styleNNWeight` getter). A new `_displayStyle` helper sets `fontFamily: 'Anthropic Sans
   Display'` (with `'Anthropic Sans Text'` as its `fontFamilyFallback`), used only by the
   large headline call sites (`this.t(20|21, W.Bold, ..., {fontFamily:DISPLAY})` in the
   prototype — onboarding/spawn headlines): `style20Bold`, `style21Bold`.

## Families table

| Family | Wired as | Usage in prototype | Status |
|---|---|---|---|
| JetBrains Mono (var. font, instanced to 400/500/600/700) | `'JetBrains Mono'` in `AppTextStyle._monoStyle` / `mono*` getters | Terminal-adjacent chrome, timestamps, PR/branch text (`this.m(...)` calls) | ✅ wired |
| Anthropic Sans Text | `'Anthropic Sans Text'` in `AppTextStyle._textStyle` / every `styleNNWeight` getter | Everything via the `t()` style helper (default body/UI text) | ✅ wired |
| Anthropic Sans Display | `'Anthropic Sans Display'` in `AppTextStyle._displayStyle` / `style20Bold`, `style21Bold` | Large headline call sites (onboarding heading, spawn...) | ✅ wired |
| Material Symbols Outlined | not in scope of this phase | Icon glyphs via `this.ic()` helper — this project already uses `Icons`/an icon font elsewhere; a components/icons phase should reconcile glyph names (`arrow_back_ios_new`, `chevron_right`, `call_split`, etc. are Material Symbols ligature names) against whatever icon set the app's core widgets already use | not evaluated here |

JetBrains Mono note: the prototype's own `@font-face` rules declare 4 near-duplicate
weight variants (400/500/600/700) that all point at the **same** embedded file — it's a
variable font (`wght` axis 400–800) whose default static instance was reused for every
declared weight. We instanced real static weights (400/500/600/700) with
`fontTools.varLib.instancer` instead of reusing one file, so weight actually changes in
the app (the prototype itself doesn't visually differ between its declared JBM weights).
Only the latin subset was extracted — cyrillic/greek/vietnamese subset files were
skipped (Flutter needs one file per weight, not per-Unicode-range subsets); non-Latin
glyphs fall back to the system monospace fallback chain already in `_monoStyle`.

## Scale — what's ACTUALLY used (not the prototype's `--fs-*` CSS tokens)

The prototype's `:root` block defines a `--fs-display-xl` … `--fs-overline` CSS custom
property scale (64/48/36/28/22/18/16/14/13/12/11px) that reads like a generic marketing-site
type ramp. **The rendered screens do not consume it.** Every element's actual font size
comes from two inline helper calls hardcoded per element:

```js
t(size, weight, color, extra)  // fontFamily: SYS (Anthropic Sans Text)
m(size, weight, color, extra)  // fontFamily: MONO (JetBrains Mono)
```

with literal, often half-point, size arguments (e.g. `this.t(12.5, W.SemiBold, ...)`).
That's the real scale — an ad-hoc, size-per-element system, not a semantic
display/heading/body ramp. It maps directly onto **this project's existing
`AppTextStyle.style<Size><Weight>` convention** (`lib/core/app_themes/text_style/`),
which already deliberately concentrates on sizes 8–13 for this dense, phone-first UI —
so no new semantic scale class was introduced. New half-point getters follow a `pNN`
naming convention (Dart identifiers can't contain `.`): `style11p5SemiBold`,
`style12p5Medium`, `style12p5SemiBold`, `style13p5Regular`, `style13p5Medium`,
`style14p5SemiBold`, `style16p5Bold`, plus mono equivalents `mono10p5Regular`,
`mono11p5Regular`, `mono13p5Regular`. Two new whole-point getters were added for the
onboarding/spawn headlines: `style20Bold`, `style21Bold`.

| Size × weight seen in prototype | Existing or new `AppTextStyle` getter |
|---|---|
| 9–17 × Regular/Medium/SemiBold/Bold | already existed (`style9Regular` … `style17Bold`) |
| 19 SemiBold, 24/26/32 Bold | already existed |
| 10.5 Regular (mono only) | `mono10p5Regular` (new) |
| 11.5 SemiBold (sans), 11.5 Regular (mono) | `style11p5SemiBold`, `mono11p5Regular` (new) |
| 12.5 Medium/SemiBold (sans) | `style12p5Medium`, `style12p5SemiBold` (new) |
| 13.5 Regular/Medium (sans), 13.5 Regular (mono) | `style13p5Regular`, `style13p5Medium`, `mono13p5Regular` (new) |
| 14.5 SemiBold (sans) | `style14p5SemiBold` (new) |
| 16.5 Bold (sans) | `style16p5Bold` (new) |
| 20 Bold, 21 Bold (sans, display headlines) | `style20Bold`, `style21Bold` (new) |

Weights map via the existing `FontWeightHelper` (`regular`=400 … `bold`=700); the
prototype's `W.ExtraBold` (800) is declared for Anthropic Sans only and unused by any
`t()`/`m()` call site, so no `extraBold` getters were added — nothing consumes them yet.

## Quirks

- Icon glyphs are Material Symbols **ligature names** (`arrow_back_ios_new`, not a
  codepoint) — reconcile against this app's actual icon widget/font in the components
  phase, not here.
- No RTL-specific font substitution logic exists in the prototype; Flutter's own
  fallback chain (`fontFamilyFallback`) is untouched beyond mono's existing
  `['Menlo', 'Courier New', 'monospace']`.
- `flutter analyze` after these changes: **No issues found!**
