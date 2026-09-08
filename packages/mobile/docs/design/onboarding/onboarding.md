# Onboarding — "Connect your desktop"

Screenshots: `onboarding-light.png`, `onboarding-dark.png` (dark is the default state per
this doc set's convention; both captured since this screen has no other state variation).

Shared docs: [`../README.md`](../README.md) (screen→feature map, global conventions) ·
[`../colors.md`](../colors.md) · [`../typography.md`](../typography.md) ·
[`../motion.md`](../motion.md) · [`../components.md`](../components.md).

## Part A — Spec

### Purpose / context

The very first screen a user sees when the app has no paired desktop (`state.screen ===
'onboarding'` in the prototype). It explains what pairing does and starts the pairing
flow. Also reachable later via Settings → "Disconnect" (returns the user here).

### Layout tree (top → bottom)

1. **Header row** (`S.onbHeaderRow`) — flex row, `padding: 4px 20px 0`, `gap: 8`.
   - Mascot image, 28×28, `objectFit: contain` (asset: the blue robot mascot PNG embedded
     in the prototype — source the actual app icon/mascot asset already in this repo,
     e.g. `assets/images/`, rather than re-extracting the prototype's copy).
   - Brand wordmark "Operator" — `style15SemiBold`, `context.skin.textPrimary`, letter
     spacing -0.2.
   - Spacer (flex: 1).
2. **Scroll body** (`S.onbScroll`) — `padding: 24px 20px 20px`, vertical scroll.
   - Heading "Connect your desktop" — **display** style, `style24Bold`-equivalent but
     note the prototype forces `fontFamily: DISPLAY` (Anthropic Sans Display) at this
     size — bottom margin 10, letter spacing -0.4, `textPrimary`. Use `AppTextStyle`'s
     display-family styling convention (see typography.md — currently only `style20Bold`/
     `style21Bold` are wired to the Display family; this heading is size 24, so either
     extend `_displayStyle` with a `style24Bold`-display variant or add one — flag this
     gap rather than silently using the Text family at 24).
   - Body copy "Pair with Operator on your computer to check on your agents, jump into
     any terminal, and drive work from your phone." — `style14Regular`,
     `context.skin.textSecondary`, line-height 1.4, bottom margin 20.
   - **Primary button** "Pair Desktop" — full-width, height 50, `radiusButton` (12),
     `context.skin.accent` background, `onAccent` text, `style17Medium`, bottom margin 28,
     press scale `AppMotion.pressScaleDefault` + `AppMotion.spring` (already the
     restyled `PrimaryButton` widget — see components.md).
   - Label "HOW IT WORKS" — `style11SemiBold`-ish (11px SemiBold), `textTertiary`,
     bottom margin 14, no extra letter-spacing beyond the prototype's default (unlike
     the design's `--tr-overline` CSS token, which is unused boilerplate per typography.md
     — the actual rendered spacing here is plain, don't add letter-spacing not backed by
     the `S.howItWorksLabel` object).
   - **3-step list** (`sc-for` over `onboardingSteps`, exactly 3 items), each row
     (`S.stepRow`): flex row, `align-items: flex-start`, gap 12, bottom margin 18.
     - Step badge: 24×24 circle, `tintGreen` background, `green` text, `style12SemiBold`,
       centered digit ("1"/"2"/"3").
     - Text column (flex: 1): title `style14SemiBold` `textPrimary` (bottom margin 2),
       hint `style12Regular` `textSecondary` line-height 1.35.

### Dummy content (verbatim — must match screenshots)

- Wordmark: **Operator**
- Heading: **Connect your desktop**
- Body: **"Pair with Operator on your computer to check on your agents, jump into any
  terminal, and drive work from your phone."**
- Button: **Pair Desktop**
- Label: **HOW IT WORKS**
- Step 1 — title **"Open Operator on your computer"**, hint **"Go to Settings → Connect
  Mobile and turn it on."**
- Step 2 — title **"Scan the code"**, hint **"Tap Pair Desktop above and point at the QR
  code on your screen."**
- Step 3 — title **"You're connected"**, hint **"Your sessions appear here, and you can
  drive them from your phone."**

### Motion

- Screen itself has no entrance animation in the prototype (verified — `isOnboarding`
  swaps in instantly, per `motion.md`'s "no screen transition" note). Don't add one.
- "Pair Desktop" button: press scale only (`AppMotion.pressScaleDefault`,
  `AppMotion.fast` + `AppMotion.spring`), no other motion.

### Verified behavior

- Tapping **"Pair Desktop"** transitions to the pairing flow. In the prototype this is a
  stub (`pairDesktop: () => this.setState({screen:'home'})` — it just jumps straight to
  the home shell, skipping pairing entirely, since this is a visual mockup with no real
  QR/network layer). In the real app this must launch the actual pairing flow:
  `lib/feature/pairing/presentation/pairing_scan_screen/` (QR scan) — do NOT wire this
  button to jump straight to the home shell as the prototype does; that's a mockup
  shortcut, not the intended behavior.
- No other interactive elements on this screen (steps are static, not tappable).

### Flutter mapping

- Feature dir: `lib/feature/onboarding/presentation/onboarding_screen/` (**already
  exists** — read it first, see Part B).
- Core widgets used: `PrimaryButton` (main_widgets/primary_button.dart).
- Custom feature widgets: the numbered step row (badge + title + hint) — small enough to
  be a private widget inside `onboarding_screen/ui/widgets/`, not a core widget (single
  call site).

## Part B — Implementation brief

**# TASK:** Restyle the existing onboarding screen to match the prototype's visual spec
above. UI-only — dummy step copy is fine to hardcode (it's static product copy, not
sample data), no backend change needed since this screen has no data dependency beyond
navigation.

**Do this FIRST, before any Dart:**
1. Read `docs/design/README.md` (screen→feature map, global conventions, "already
   implemented" inventory) and this file's Part A in full.
2. Invoke the `flutter-knowledge` skill — it is the authority on this project's
   architecture, Cubit conventions, and screen/body split. Only then touch any `.dart`
   file.

**Target feature — exact path (non-negotiable):**
`lib/feature/onboarding/presentation/onboarding_screen/` — every file for this screen
goes here and nowhere else.

**Already exists — do NOT recreate:**
- The screen file(s) under `onboarding_screen/ui/` already exist — read them before
  editing. This is a **restyle**, not a rebuild: keep whatever cubit/navigation logic is
  already correct, change colors/type/spacing/copy to match Part A.
- `PrimaryButton` (restyled in Phase 5, already accent-colored) — use it, don't hand-roll
  a button.

**Files to create/change:**
- `onboarding_screen/ui/onboarding_screen.dart` (or wherever the body currently lives) —
  restyle per Part A's layout tree.
- New small widget for the numbered step row, under `onboarding_screen/ui/widgets/`, if
  one doesn't already exist in a matching shape.

**Key implementation points:**
1. The heading is 24px in the **Display** family — `AppTextStyle` currently only wires
   `style20Bold`/`style21Bold` to Display (see typography.md). Either add a
   `style24BoldDisplay`-style getter to `AppTextStyle` (preferred — keep the convention
   consistent) or confirm with the user before improvising a different approach.
2. **Do not wire "Pair Desktop" to jump straight to the home shell** the way the
   prototype's stub does — route to the real pairing flow
   (`lib/feature/pairing/presentation/pairing_scan_screen/`).
3. Mascot image: use this repo's existing app icon/mascot asset, not a re-extracted copy
   from the prototype bundle.
4. No entrance transition on this screen (see Motion above) — don't add one.

**Dummy data:** none needed — all copy is static, see "Dummy content" above for exact
strings.

**Localization:** this project's CLAUDE.md overrides the generic Flutter convention —
**no `LocaleKeys`/easy_localization**, user-facing copy is inline English. Do not add
translation keys for this screen's copy.

**Definition of done:**
- `flutter analyze` clean, no new warnings.
- Matches `onboarding-light.png` and `onboarding-dark.png` in both themes.
- "Pair Desktop" routes to the real pairing flow, not a stub home-shell jump.
- Step list renders exactly the 3 steps with the verbatim copy above.
