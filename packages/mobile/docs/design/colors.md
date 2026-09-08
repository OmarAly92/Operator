# Colors

Source: `docs/design/Operator Mobile - standalone.html` (Pencil prototype), `LIGHT`/`DARK`
token objects embedded in its script (~line 2785-2808 of the decoded template). This fully
replaces the prior blue Material palette in `lib/core/app_themes/colors/` (explicit user
decision, 2026-09-08).

## Brand

| Token | Hex | Notes |
|---|---|---|
| accent (brand green) | `#1ACB64` | Identical value in both themes — this is the "Operator green" wordmark/brand color, distinct from the semantic `green` status color below. |

**Do not conflate `accent` and `green`.** They coincide only in dark mode:

| Theme | `accent` | `green` (status: mergeable/merged/approved/done) |
|---|---|---|
| Light | `#1ACB64` | `#1F8A5B` (different) |
| Dark | `#1ACB64` | `#1ACB64` (same) |

## Semantic tokens

| Token | Light | Dark | Skin getter |
|---|---|---|---|
| Page background | `#faf7f2` | `#18171c` | `bgBase` |
| Side rail / nav background | `#ffffff` | `#131218` | `bgSide` |
| Board column background | `#faf7f2` | `#18171c` | `bgColumn` |
| Card / surface | `#ffffff` | `#1f1e24` | `bgSurface` |
| Elevated surface (menu, popover) | `#f4efe6` | `#28262e` | `bgElevated` |
| Elevated hover | `#ebe4d6` | `#2a2832` | `bgElevatedHover` |
| Subtle fill | `rgba(26,22,18,.05)` | `rgba(255,255,255,.05)` | `bgSubtle` |
| Chrome fill (toggle track / segmented control bg) | `#ebe4d6` | `#131218` | `bgChrome` *(new)* |
| Text primary | `#1a1612` | `#ffffff` | `textPrimary` |
| Text secondary | `#3d362e` | `#d9d8de` | `textSecondary` |
| Text tertiary | `#6b6354` | `#a09ea8` | `textTertiary` |
| Text faint | `#9c9381` | `#6f6d78` | `textFaint` |
| Border subtle | `rgba(26,22,18,.06)` | `rgba(255,255,255,.04)` | `borderSubtle` |
| Border default | `#ebe4d6` | `rgba(255,255,255,.07)` | `borderDefault` |
| Border strong | `#d8cebd` | `rgba(255,255,255,.12)` | `borderStrong` |
| Blue (status) | `#1f8ee0` | `#47bfff` | `blue` |
| Orange (status: working) | `#96590d` | `#e89527` | `orange` |
| Amber (status: needs input) | `#856010` | `#f0b45c` | `amber` |
| Red (status: failing) | `#c43a3a` | `#ff7575` | `red` |
| Purple (status: merged/misc) | `#1a6fb0` | `#1f8ee0` | `purple` |
| Green (status: passed) | `#1f8a5b` | `#1acb64` | `green` |
| Coral | `#c47a18` | `#e89527` | `coral` *(new)* |
| Tint blue | `rgba(31,142,224,.10)` | `rgba(71,191,255,.10)` | `tintBlue` |
| Tint orange | `rgba(232,149,39,.14)` | `rgba(232,149,39,.16)` | `tintOrange` |
| Tint amber | `rgba(232,149,39,.14)` | `rgba(232,149,39,.16)` | `tintAmber` |
| Tint red | `rgba(196,58,58,.10)` | `rgba(255,117,117,.14)` | `tintRed` |
| Tint green | `rgba(26,203,100,.14)` | `rgba(26,203,100,.16)` | `tintGreen` |
| Tint purple | `rgba(31,142,224,.10)` | `rgba(71,191,255,.10)` | `tintPurple` |
| Shimmer base | `#efe9dd` | `#26242d` | `shimmerBase` *(new)* |
| Shimmer highlight | `#fbf9f5` | `#332f3c` | `shimmerHi` *(new)* |
| On-accent (text/icon on accent fills) | `#18171c` | `#18171c` | `onAccent` |
| Scrim (dialog/sheet backdrop) | `rgba(26,22,18,.55)` | `rgba(26,22,18,.55)` | `scrim` |
| Accent (brand) | `#1acb64` | `#1acb64` | `accent` |
| Accent tint | `rgba(26,203,100,.14)` | `rgba(26,203,100,.16)` | `accentTint` |
| Attention | `#1acb64` | `#1acb64` | `attention` |

## Judgment calls

- **`scrim` is theme-invariant in the prototype.** Every dialog/sheet backdrop
  (`S.scrim`, `sk-dialog-scrim`) uses the single value `rgba(26,22,18,0.55)` regardless of
  `dark` state — there is no dark-mode override in the source. Both `LightSkin.scrim` and
  `DarkSkin.scrim` are now set to `Color(0x8C1A1612)`. This replaces the old two-tone black
  scrims (`0x73000000` light / `0x99000000` dark).
- **`attention` = `accent`.** The prototype never defines a separate "attention" color — the
  one attention-drawing UI element found (`bellBadge`, the notification-count badge on the
  Agents tab bell icon, `lib/feature/notification` territory) is styled with
  `background: skin.accent` directly. So `attention` now equals `accent` (`#1ACB64`) in both
  themes, rather than reusing `amber` as the old palette did.
- **`accentTint` has no direct prototype token** — it's never referenced in the source. Derived
  it by applying the same alpha the prototype uses for `tintGreen` (0.14 light / 0.16 dark) to
  `accent`'s own RGB (26,203,100) rather than `green`'s RGB. In dark mode this is numerically
  identical to `tintGreen` (since `accent == green` there); in light mode it differs from
  `tintGreen` because `accent != green` in light mode — this is intentional, not a bug.
- Unchanged, prototype has no equivalent token: none — every existing `AppSkin` getter had a
  same-named counterpart in the prototype's `LIGHT`/`DARK` objects except the four new ones
  added below (which the prototype has but the old skin didn't).

## New getters added to `AppSkin`

- `coral` — a warm tertiary hue distinct from `orange`/`amber`. Not consumed by any screen we've
  extracted yet in the prototype's data-driven paths; kept for parity since it's a first-class
  token in both `LIGHT`/`DARK` objects and may surface in a status legend not yet walked.
- `shimmerBase` / `shimmerHi` — the two-stop gradient for skeleton/shimmer loading states.
  See Motion doc for the `saShimmer` keyframe that animates between them.
- `bgChrome` — background for chrome-y controls like the light/dark theme toggle track and other
  segmented controls (the prototype's dev harness reads `dark ? '#1f1e24' : '#fff'` for its own
  toggle row, which is a harness-only value, not `bgChrome` — `bgChrome` instead maps to the
  prototype's `bgChrome` token used elsewhere, e.g. behind the desktop-connection status row).

## Shadow recipes

| Use | CSS box-shadow | Notes |
|---|---|---|
| Dialog | `0 24px 48px rgba(26,22,18,0.32)` | Confirm/remove-desktop dialog. |
| Bottom sheet | `0 18px 40px rgba(26,22,18,0.22)` | Add/edit-connection and menu sheets. |
| Segmented toggle row | `0 1px 2px rgba(0,0,0,0.08)` | Light-only harness toggle; not app chrome. |
| Toggle/switch thumb | `0 1px 3px rgba(0,0,0,0.3)` | Worktree switch, other on/off toggles. |
| Floating "jump to latest" button | `0 4px 14px rgba(0,0,0,0.20)` | Terminal/chat scroll-to-bottom FAB. |
| Nav stepper (segmented pill) | `0 2px 8px rgba(0,0,0,0.10)` | e.g. PR filter stepper. |
| Brand glow — resting | `0 6px 18px rgba(26,203,100,0.25)` | Onboarding mascot/orb, accent-colored glow. |
| Brand glow — emphasized (breathing) | `0 12px 44px rgba(26,203,100,0.35)` | Same orb during its `saOrbFloat` loop peak. |
| Generic elevated icon button | `0 4px 12px rgba(0,0,0,0.25)` | e.g. add-connection FAB. |

These are documented as CSS values for reference; Flutter widgets should express them as
`BoxShadow`/`List<BoxShadow>` in the core widget that owns each use (dialog shape, sheet shape,
FAB), not duplicated ad hoc per screen — see `components.md` (Phase 5).
