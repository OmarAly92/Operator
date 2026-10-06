# A — Apple Liquid Glass inventory (iOS 26, with 26.x and iOS 27 deltas)

Master checklist of what "complete" means for a natively-identical Flutter reproduction of Apple's
Liquid Glass on iPhone (iPad notes where they change the phone behaviour).

Compiled 2026-09-26. iOS 27 shipped this month, so the live Apple docs and HIG are iOS 27-era text;
every item is tagged with the version it belongs to where the source allows.

## 0. How to read this file

**Source keys** (full URLs in §12):

| Key | Source |
|---|---|
| HIG-<page> | Human Interface Guidelines page, e.g. HIG-Materials = https://developer.apple.com/design/human-interface-guidelines/materials |
| SUI | SwiftUI reference docs (https://developer.apple.com/documentation/swiftui/...) |
| UIK | UIKit reference docs (https://developer.apple.com/documentation/uikit/...) |
| ADOPT | Article "Adopting Liquid Glass" https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass |
| APPLY | Article "Applying Liquid Glass to custom views" https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views |
| W219, W356, W323, W284, W310, W256, W243, W208, W220, W361, W278, W102 | WWDC25 session at https://developer.apple.com/videos/play/wwdc2025/<id>/ |
| W26-102, W26-269, W26-278, W26-289, W26-292, W26-251, W26-8120 | WWDC26 session at https://developer.apple.com/videos/play/wwdc2026/<id>/ |
| MWA208, MWA201 | Meet with Apple sessions https://developer.apple.com/videos/play/meet-with-apple/208/ (app showcase + Apple design team) and /201/ (WWDC25 recap; fetched as a summary, so API spellings from it are unreliable) |
| NEWS | Apple Newsroom 2025-06-09 https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ |
| 3P-<name> | Third-party write-up (see §11 and §12) |

**Evidence tags** used on every claim that carries a value or a behaviour:

- **[stated]** Apple says it in docs, HIG or a session transcript.
- **[code]** the value appears in Apple sample/session code (an example value, not a system constant).
- **[measured]** a third party measured it on device/simulator.
- **[inferred]** our reading of Apple's words into an implementation rule. Treat as a hypothesis to verify.
- **[unknown]** nobody documents it; must be measured (see §9 "values to measure").

**The single most important caveat.** Apple publishes almost no numbers for the material or its motion.
No Apple doc, HIG page or WWDC25/26 transcript gives a blur radius, tint opacity, shadow value,
duration, spring response/damping, default container spacing, fixed-spacer width, tab bar height,
minimized-tab size, sheet inset or sheet corner radius [stated-by-absence across HIG, SUI, UIK, W219,
W356, W323, W284]. Everything numeric in this file is either an Apple example value [code], a
third-party measurement [measured], or explicitly marked [unknown].

**Version facts that change scope**

- iOS 26.0 (Sept 2025): Liquid Glass ships; apps adopt it by building with the iOS 26 SDK [W102].
- iOS 26.1: user setting Settings > Display & Brightness > Liquid Glass: **Clear** (default) or
  **Tinted** ("increased opacity and contrast"); unavailable while Reduce Transparency or Increase
  Contrast is on [support.apple.com iPhone guide, 3P-Engadget]. New API: `GlassButtonStyle.init(_:)`,
  `tabViewBottomAccessory(isEnabled:content:)`, `UISheetPresentationController.Detent.backgroundEffect` [SUI, UIK].
- Betas (context for older screenshots): beta 3 (2025-07-08) made bars much more frosted/opaque; beta 4 (2025-07-22) restored transparency ("a refined balance between the heavy liquid ... and the more frosted look in beta 3") [3P-S22, S23]. Match 26.0 GA and later, never beta-era captures.
- iOS 26.2: Lock Screen clock Glass/Solid with a transparency slider [3P-S26, S27].
- iOS 26.4: Accessibility "Reduce Bright Effects" (tones down the bright flash on interaction); Tinted respects light/dark; iPad private `UseFloatingTabBar` removed [3P-S28, S29, S30].
- iOS 26 accessibility: "Show Borders" replaced "Button Shapes" (Settings > Accessibility > Display &
  Text Size) [3P-iDownloadBlog, 3P-OSXDaily].
- iOS 27.0 (Sept 2026): material retuned: "more effectively diffuses complex content", "a darkened
  edge along with brighter specular highlights"; Settings slider "anywhere from ultra clear to fully
  tinted"; "When content scrolls under floating bars, a uniform toolbar appears across the top"; apps
  get this without recompiling [W26-102]. `UIDesignRequiresCompatibility` is ignored when building
  for iOS 27 or later, so the opt-out is gone [UIK Info.plist key page]. See §8 for the full delta.

---

## 1. Master checklist (component index)

Each row is one thing a Flutter port must reproduce. "§" points to the detailed entry.

| # | Component / behaviour | Native API (SwiftUI / UIKit) | § |
|---|---|---|---|
| 1 | Regular glass material | `glassEffect(.regular)` / `UIGlassEffect(style: .regular)` | 2.1 |
| 2 | Clear glass + dimming layer | `Glass.clear` / `UIGlassEffect.Style.clear` | 2.2 |
| 3 | Identity glass (no-op / reveal-on-interaction) | `Glass.identity` | 2.3 |
| 4 | Tinted glass | `Glass.tint(_:)` / `UIGlassEffect.tintColor` | 2.4 |
| 5 | Interactive glass press response | `Glass.interactive()` / `UIGlassEffect.isInteractive` | 2.5 |
| 6 | Lensing / edge refraction | implicit in every glass | 2.6 |
| 7 | Specular rim highlight (+ device motion) | implicit | 2.7 |
| 8 | Adaptive shadow | implicit | 2.8 |
| 9 | Light/dark flipping by backdrop luminance (small elements only) | implicit | 2.9 |
| 10 | Size-dependent thickness/opacity | implicit | 2.10 |
| 11 | Vibrant foreground (labels/symbols on glass) | implicit; `UIVibrancyEffect`-like | 2.11 |
| 12 | Ambient colour spill on large glass | implicit | 2.12 |
| 13 | Materialize / dematerialize (appear/disappear) | `glassEffectTransition(.materialize)` / animate `UIVisualEffectView.effect` | 2.13 |
| 14 | Glass container, shared sampling, droplet merging | `GlassEffectContainer(spacing:)` / `UIGlassContainerEffect.spacing` | 2.14 |
| 15 | Union of distant shapes into one glass | `glassEffectUnion(id:namespace:)` | 2.15 |
| 16 | Identity morph between glass shapes | `glassEffectID(_:in:)` + `GlassEffectTransition.matchedGeometry` | 2.16 |
| 17 | Default capsule shape, fixed and concentric corners | `DefaultGlassEffectShape`, `ConcentricRectangle`, `.rect(corners:)`, `containerShape`, `UICornerConfiguration` | 2.17 |
| 18 | Corner-adapted layout regions | `UIView.LayoutRegion.safeArea/margins(cornerAdaptation:)` | 2.18 |
| 19 | Scroll edge effect (soft / hard / automatic) | `scrollEdgeEffectStyle(_:for:)` / `UIScrollEdgeEffect` | 2.19 |
| 20 | Edge effect shaped by floating controls | `safeAreaBar` / `UIScrollEdgeElementContainerInteraction` | 2.20 |
| 21 | Background extension (mirror + blur under sidebar) | `backgroundExtensionEffect()` / `UIBackgroundExtensionView` | 2.21 |
| 22 | Content layer: standard materials + vibrancy | `.ultraThinMaterial` … `.thickMaterial` | 2.22 |
| 23 | Content scrolls under all bars (transparent bars) | default bar appearance | 2.23 |
| 24 | Floating tab bar (iPhone) | `TabView` / `UITabBarController` | 3.1 |
| 25 | Tab selection indicator lens (drag across tabs) | system only, no API | 3.2 |
| 26 | Tab bar minimize on scroll | `tabBarMinimizeBehavior` / `UITabBarController.MinimizeBehavior` | 3.3 |
| 27 | Tab bar bottom accessory (expanded/inline) | `tabViewBottomAccessory` / `UITabAccessory` | 3.4 |
| 28 | Search tab (separate circle, morphs into field) | `Tab(role: .search)` / `UISearchTab` | 3.5 |
| 29 | Prominent tab (iOS 27) | `Tab(role: .prominent)` | 3.6 |
| 30 | Tab badge | `.badge(_:)` | 3.7 |
| 31 | iPad top tab bar / sidebar-adaptable morph | `.sidebarAdaptable` / `UITab` | 3.8 |
| 32 | Floating glass sidebar + edge-to-edge inspector | `NavigationSplitView`, `.inspector` / `UISplitViewController` | 3.9 |
| 33 | Navigation bar: transparent, glass button groups | `.toolbar` / `UINavigationBar` | 3.10 |
| 34 | Back button (standard glass circle) | system | 3.11 |
| 35 | Large title scrolling under bar; inline title; subtitle | `navigationTitle`, `navigationSubtitle`, `.largeTitle`/`.largeSubtitle` placements / `UINavigationItem.subtitle`, `largeSubtitleView` | 3.12 |
| 36 | Toolbar item grouping on shared glass | `ToolbarItemGroup`, `ToolbarSpacer`, `sharedBackgroundVisibility` / `sharesBackground`, `hidesSharedBackground`, `fixedSpace()` | 3.13 |
| 37 | Prominent (tinted) toolbar action | `.buttonStyle(.glassProminent)` in toolbar / `UIBarButtonItem.Style.prominent` | 3.14 |
| 38 | Bottom toolbar (floating) | `.bottomBar` / `UIToolbar` | 3.15 |
| 39 | Toolbar morph across push/pop | automatic; `UIBarButtonItem.identifier` | 3.16 |
| 40 | Bar button badges | `.badge` on item content / `UIBarButtonItem.badge` | 3.17 |
| 41 | Navigation bar minimization (iOS 27) | `toolbarMinimizationBehavior(_:for:)` / `UIBarMinimization` | 3.18 |
| 42 | Toolbar overflow + visibility priority, pinned trailing, padding removal (iOS 27) | `ToolbarOverflowMenu`, `visibilityPriority`, `.topBarPinnedTrailing`, `contentMarginsRemoved` / `isPaddingRemoved` | 3.19 |
| 43 | Search field in bottom toolbar, minimized search button, field above keyboard | `searchable`, `searchToolbarBehavior(.minimize)`, `DefaultToolbarItem(kind: .search)` / `preferredSearchBarPlacement = .integrated*`, `searchBarPlacementBarButtonItem` | 3.20 |
| 44 | Scope bar / tokens | `searchScopes`, tokens | 3.21 |
| 45 | Sheets: inset floating glass at partial detents, opaque at full | `presentationDetents` / `UISheetPresentationController` | 4.1 |
| 46 | Sheet grabber, dimming, background interaction | `presentationDragIndicator`, `presentationBackgroundInteraction` / `prefersGrabberVisible`, `largestUndimmedDetentIdentifier` | 4.2 |
| 47 | Sheet zooms out of its source button | `matchedTransitionSource` on toolbar content + `.navigationTransition(.zoom)` / `.zoom(sourceBarButtonItemProvider:)` | 4.3 |
| 48 | Sheet cross-fade presentation (iOS 27) | `NavigationTransition.crossFade` | 4.4 |
| 49 | Popover morphs from, and replaces, its bar button | `.popover` / `sourceItem` | 4.5 |
| 50 | Menus / pull-down buttons pop open from the button | `Menu` / `UIMenu` on `UIButton`/`UIBarButtonItem` | 4.6 |
| 51 | Context menu (preview + dim) | `.contextMenu` / `UIContextMenuInteraction` | 4.7 |
| 52 | Edit menu | `UIEditMenuInteraction` | 4.8 |
| 53 | Alerts | `.alert` / `UIAlertController(.alert)` | 4.9 |
| 54 | Action sheets / confirmation dialogs from source | `.confirmationDialog` / `UIAlertController(.actionSheet)` + `sourceItem` | 4.10 |
| 55 | Push zoom transition; interruptible navigation | `navigationTransition(.zoom)`, `matchedTransitionSource` | 4.11 |
| 56 | Glass button | `.buttonStyle(.glass)` / `UIButton.Configuration.glass()` | 5.1 |
| 57 | Prominent glass button | `.glassProminent` / `.prominentGlass()` | 5.2 |
| 58 | Clear glass buttons | `.glass(.clear)` / `.clearGlass()`, `.prominentClearGlass()` | 5.3 |
| 59 | Button shapes and sizes (capsule default, circle, extra large) | `buttonBorderShape`, `controlSize(.extraLarge)` | 5.4 |
| 60 | Toggle / switch (knob lifts into glass) | `Toggle` / `UISwitch` | 5.5 |
| 61 | Slider (glass thumb, momentum, stretch, ticks, neutral value, thumbless) | `Slider` / `UISlider` | 5.6 |
| 62 | Segmented control (selection lifts into glass) | `Picker(.segmented)` / `UISegmentedControl` | 5.7 |
| 63 | Stepper | `Stepper` / `UIStepper` | 5.8 |
| 64 | Pickers (menu, date compact/inline/wheels) | `Picker`, `DatePicker` | 5.9 |
| 65 | Page control (translucent platter) | `UIPageControl.backgroundStyle` | 5.10 |
| 66 | Text fields and search field glyphs | `TextField` / `UITextField`, `UISearchBar` | 5.11 |
| 67 | Lists and forms (taller rows, rounder sections, title-case headers) | `List`, `Form(.grouped)` / `UICollectionView` list | 5.12 |
| 68 | Progress / thumbless slider as progress | `ProgressView`, `UISlider.sliderStyle = .thumbless` | 5.13 |
| 69 | Swipe actions | `swipeActions` / `UISwipeActionsConfiguration` | 5.14 |
| 70 | iPad pointer hover platter | pointer effects | 5.15 |
| 71 | System keyboard and system sheets (share sheet, etc.) | system | 5.16 |
| 72 | App icon appearances (default/dark/clear/tinted) | Icon Composer | 6.1 |
| 73 | Widgets clear/tinted (accented rendering) | `widgetRenderingMode`, `widgetAccentedRenderingMode` | 6.2 |
| 74 | Reduce Transparency variant | system setting | 7.1 |
| 75 | Increase Contrast variant | system setting | 7.2 |
| 76 | Reduce Motion variant | system setting | 7.3 |
| 77 | Show Borders | system setting (`accessibilityShowButtonShapes`) | 7.4 |
| 78 | Liquid Glass Clear/Tinted setting (26.1) and Clear-to-Tinted slider (27) | system setting | 7.5 |
| 79 | Light/Dark appearance and inactive-window recede (iPad) | `colorScheme`, `appearsActive` | 7.6 |
| 80 | Typography/colour retune (system colours, bolder left-aligned alerts) | system | 7.7 |

---

## 2. The material and its foundations

Each entry: **API** · **Anatomy** · **Interaction & motion** · **Accessibility** · **Numbers** · **Sources**.

### 2.1 Regular glass

- **API.** SwiftUI `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` (iOS 26.0; not visionOS). UIKit `UIVisualEffectView(effect: UIGlassEffect(style: .regular))` (iOS 26.0). `struct Glass` has exactly five members: `regular`, `clear`, `identity`, `tint(_ color: Color?)`, `interactive(_ isEnabled: Bool = true)`; no iOS 27 additions [SUI Glass].
- **Anatomy.**
  - A glass shape is drawn *behind* the view and the glass *foreground* treatment is applied *over* the view; the glass fills the view's bounds including padding already applied [SUI glassEffect].
  - Default shape is a capsule [SUI DefaultGlassEffectShape; W284 "By default, the glass is in a capsule shape"].
  - "The regular variant blurs and adjusts the luminosity of background content to maintain legibility" [HIG-Materials]. Most system components use it; use it for text-heavy components such as **alerts, sidebars, popovers** [HIG-Materials].
  - It is a composite of layers: highlights, shadow, tint, dynamic range, illumination; "each layer continuously adapts based on what's behind it" [W219].
  - Glass "has no color of its own"; by default it takes colour from what is directly behind it [HIG-Color].
- **Interaction & motion.** Static unless `interactive` (2.5). Adapts continuously to what scrolls beneath (2.8, 2.9).
- **Rules.** Only in the functional (navigation/control) layer, never the content layer, except transient controls (slider/toggle thumbs) that take on glass *while activated* [HIG-Materials]. "Use Liquid Glass effects sparingly" [HIG-Materials]. Apply `glassEffect` after other appearance modifiers [APPLY]. Apply the material to the control itself, "not its inner views" [W356].
- **Accessibility.** Changes under Reduce Transparency, Increase Contrast and the user's Liquid Glass preference (7.x) [HIG-Materials].
- **Numbers.** None published. Blur radius, luminosity curve, tint opacity: [unknown].
- **Sources.** https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:) · https://developer.apple.com/documentation/uikit/uiglasseffect · https://developer.apple.com/design/human-interface-guidelines/materials · https://developer.apple.com/videos/play/wwdc2025/219/

### 2.2 Clear glass and its dimming layer

- **API.** `Glass.clear`; `UIGlassEffect.Style.clear`; buttons `.buttonStyle(.glass(.clear))`, `UIButton.Configuration.clearGlass()` / `.prominentClearGlass()` [SUI, UIK].
- **Anatomy.** "Highly translucent"; for components floating over media (photos, video) [HIG-Materials]. "Does not have adaptive behaviors. It is permanently more transparent" [W219]. Never mix Regular and Clear in one UI [W219].
- **Dimming layer (the part implementations miss).**
  - Clear glass does not guarantee legibility by itself; put a dimming layer under it [SUI Glass.clear]. "Without it, legibility gets noticeably worse" [W219].
  - HIG: if the content behind is bright, add a **dark dimming layer of 35% opacity**; not needed if content is already dark or AVKit controls supply their own dimming [HIG-Materials] [stated].
  - Apple's SwiftUI doc example uses `.background(.black.opacity(0.3))` under a clear-glass label [SUI Glass.clear] [code]. So Apple's own values are 30% (example) and 35% (guideline).
  - Small footprints can use *localized* dimming so the rest of the media keeps its vibrancy [W219].
  - Use clear only when all three hold: over media-rich content; the content layer tolerates dimming; the content on top is bold and bright [W219].
- **Numbers.** 35% dark dim [stated]; 0.3 black in example [code].
- **Sources.** HIG-Materials; https://developer.apple.com/documentation/swiftui/glass/clear ; W219.

### 2.3 Identity glass

- **API.** `Glass.identity`: content renders as if no glass were applied [SUI].
- **Use.** Toggle glass off without changing the view tree (keeps identity/animation state) [inferred from SUI]. Tide Guide uses it so a view "doesn't change the appearance ... until you interact with it"; on scrub it "adds a soft, subtle highlight beneath" and the container "scales and feels very tactile" [MWA208].
- **Sources.** https://developer.apple.com/documentation/swiftui/glass/identity ; MWA208.

### 2.4 Tinted glass

- **API.** `Glass.tint(_ color: Color?)` (nil = untinted); `UIGlassEffect.tintColor`; prominent styles (`.glassProminent`, `.prominentGlass()`, `UIBarButtonItem.Style.prominent`) tint with the accent/tint colour [SUI, UIK].
- **Anatomy.**
  - Tint is a property *of the material*, not paint on top: "Selecting a color generates a range of tones that are mapped to content brightness underneath the tinted element ... changing its hue, brightness and saturation depending on what's behind without deviating too much from the intended color" [W219].
  - "Tinted glass color automatically adapts to a vibrant version" [W284]; "the tint also uses a vibrant color that adapts to the content behind it" [W323].
  - A solid fill "is completely opaque and breaks the visual character of Liquid Glass"; tint "feels more transparent" [W219].
  - Same tint system spans labels, text, fully tinted buttons and the Lock Screen clock [W219].
- **Rules.** Tint only primary elements/actions; "When every element is tinted, nothing stands out"; put brand colour in the content layer [W219, HIG-Color, W26-251]. To emphasise, tint the *background*, not the symbol/text (the Done button) [HIG-Color]. One or two prominent buttons per view [HIG-Buttons]. One `.prominent` primary action per toolbar, trailing [HIG-Toolbars].
- **Motion.** Tint animates alongside other glass properties [W284 code animates `tintColor` with label colour].
- **Numbers.** None. The brightness-to-tone mapping curve is [unknown].
- **Sources.** W219; W284; https://developer.apple.com/documentation/swiftui/glass/tint(_:) ; HIG-Color.

### 2.5 Interactive glass (press / hold response)

- **API.** `Glass.interactive(_ isEnabled: Bool = true)`; `UIGlassEffect.isInteractive` (default false) [SUI, UIK]. Glass buttons get the same behaviour automatically; custom interactive glass "reacts to touch and pointer the same way" as `.glass` buttons [APPLY]. On iOS use it for custom controls or containers with interactive elements [W323].
- **Behaviour (all [stated]).**
  - "Glass reacts to user interaction by scaling, bouncing, and shimmering, matching the effect provided by toolbar buttons and sliders" [W323].
  - "When tapping the button, it scales and bounces" [W284].
  - "Responds to interaction by instantly flexing and energizing with light"; "an inherent gel-like flexibility ... as it moves in tandem with your interaction" [W219].
  - "The material illuminates from within as a form of feedback. Starting right under your fingertips, the glow spreads throughout the element and onto any Liquid Glass elements nearby" [W219].
  - Tide Guide: buttons "expand and morph under your finger" ... "snappy and with a little haptic feedback" [MWA208].
  - Direct touch gets "more emphasis"; trackpad input a "more subdued effect" [HIG-Motion].
  - macOS 27 adds a click-bounce effect for glass ("subtly bounces when clicked") [W26-289]; iOS already had it.
- **Reproduce.** Press-down: scale up (not down), glow radiating from the touch point, spilling onto neighbouring glass in the same container; drag: gel stretch following the finger; release: spring back with overshoot ("bounce"); optional light haptic. [inferred from the quotes]
- **Accessibility.** Reduce Motion "disables any elastic properties" [W219].
- **Numbers.** Press scale factor, glow radius and spring: [unknown] (the "1.1" scale in circulation comes from sample code, not a capture). Measured: press brightening ≈ +15 luma in light mode, lift in 150 ms, collapse in 60 ms [3P-S42, light mode only]. UIKit docs paraphrase per 3P-S34: "the glass expands and various highlights are applied when the user taps". iOS 26.4 "Reduce Bright Effects" tones down this flash [3P-S29].
- **Sources.** https://developer.apple.com/documentation/swiftui/glass/interactive(_:) ; https://developer.apple.com/documentation/uikit/uiglasseffect/isinteractive ; W219; W323; W284.

### 2.6 Lensing and edge refraction

- **Anatomy.**
  - "The primary way Liquid Glass visually defines itself is through ... Lensing"; "Where as previous materials scattered light, this new set of materials dynamically bends, shapes, and concentrates light in real time" [W219].
  - "Designed to refract content from below it, reflect light from around it, and have responsive lensing along its edges" [W102]. Refraction is concentrated at the rim; the centre is a comparatively clean (lightly blurred) view of the content [inferred from W102/W219].
  - Glass "samples content from an area larger than itself" [W323, W310], so edge lensing can pull in content from outside the shape's bounds.
  - Larger glass has "more pronounced lensing and refraction effects" (2.10) [W219].
  - Observed optics: edge distortion, spherical aberration (off-centre content out of focus) and chromatic aberration at edges and in the tab lens [3P-S19].
- **Third-party optical model (approximation, not Apple's).** kube.io: Apple "appears to favor convex profiles (except for the Switch component)"; squircle bezel `y = ⁴√(1 − (1 − x)⁴)`, Snell refraction with n = 1.5, one refraction event; the author states it approximates rather than matches [3P-S39]. Flutter/Metal recreations use n = 1.1–1.5, thickness 6–30, and chromatic dispersion as tunables [3P-S40, S41, S42 IMITATION].
- **Sources.** W219; W102; W323; https://kube.io/blog/liquid-glass-css-svg/.

### 2.7 Specular rim highlight and device motion

- **Anatomy.** "Light sources ... shine on the material producing highlights that respond to geometry"; on interactions such as lock/unlock "these lights move in space, causing light to travel around the material, defining its silhouette. And in some cases, the lighting responds to device motion" [W219]. "Dynamically reacts to movement with specular highlights" [NEWS]. On icons: "Based on gyro input, you can see light moving on the edge of the icon" [W220]. Sharp corners break the travelling highlight, prefer continuous rounded curves [W220].
- **iOS 27.** "Brighter specular highlights" and "a darkened edge" [W26-102].
- **Third-party observations.** "A simple rim light effect ... its intensity varies based on the angle of the surface normal relative to a fixed light direction" [3P-S39]. Home Screen icons show highlights at the top-left *and* bottom-right corners [3P-S51]; recreations add an opposite-side highlight (light at ~135°, upper-left) [3P-S40, S41, S42 IMITATION]. Tilt-driven highlights are only confirmed on Home Screen icons and the Lock Screen, not on in-app bars or buttons [3P-S19, S48].
- **Reproduce.** A thin rim highlight tracing the shape outline, strongest where the surface normal faces the light (upper-left) with a weaker opposite highlight; move it with device attitude only where Apple demonstrably does (icons, Lock Screen; "in some cases" for UI) [inferred]. iOS 27 look adds a darkened edge and brighter specular [stated; exact geometry unknown].
- **Sources.** W219; W220; NEWS; W26-102.

### 2.8 Adaptive shadow

- "As text scrolls underneath, shadows become more prominent to create additional separation" [W219]. Glass "increases the opacity of its shadow when it is over text ... lowers the opacity of its shadow when it is over a solid light background" [W219]. Larger glass "casts deeper, richer shadows" [W219]. Large glass shadows pick up nearby colour ("bleeds into the shadow") [W219]. Icon Composer exposes Neutral vs Chromatic shadow (chromatic = artwork colour spills onto the background) [W361].
- **Numbers.** [unknown].

### 2.9 Light/dark flipping by backdrop luminance

- **Small elements flip, large ones do not.** "Small elements like navbars and tabbars, constantly adapt ... They also flip from light to dark based on the background"; "Bigger elements, like menus or sidebars also adapt ... but they don't flip from light to dark. Their surface area is too big and transitions like these would be distracting" [W219].
- Glyphs on glass flip with it: "symbols and glyphs on top of Liquid Glass ... flip from light to dark and vice versa, mirroring the glass's behavior to maximize contrast. All content placed on the Regular variant will automatically receive this treatment" [W219]. On toolbars/tab bars symbols and text are monochrome and darken over light content, lighten over dark content [HIG-Color].
- Works "independently of light and dark mode": small glass can be dark while the app is in light mode [MWA201 summary]. "Depending on the colors behind, the glass and its content will switch to light or dark mode automatically, when using dynamic colors" [W284]. AppKit: toolbar glass switches when scrolled content "is especially bright or dark" [W310].
- A container gives its members one shared decision ("enforces a uniform adaptation") [W284, W310].
- Scroll edge effect switches to "a subtle dimming" when dark content flips the glass to dark style [W219].
- **Numbers.** Luminance thresholds and hysteresis [unknown]; the flip is animated (cross-fade) [inferred].

### 2.10 Size-dependent thickness

- "Glass adapts the appearance based on its size. A larger size is more opaque. A smaller size is clearer, and switches between light and dark mode automatically" (demo sizes 250×88 vs 150×44) [W284].
- "When glass flexes and morphs to larger sizes – like when presenting a menu from a toolbar button – its material characteristics change to simulate a thicker, more substantial material. It casts deeper, richer shadows, has more pronounced lensing and refraction effects, and a softer scattering of light" [W219].
- Sidebar glass "is more opaque" than bar glass [HIG-Color].
- **Reproduce.** Parameterise every glass property by size (and interpolate it during a morph, so a button growing into a menu thickens continuously) [inferred].

### 2.11 Vibrant foreground on glass

- SwiftUI "automatically uses a vibrant text color that adapts to maintain legibility against colorful backgrounds" [W323]. UIKit labels in the effect view's `contentView` become vibrant "based on its textColor" (`.secondaryLabel` example) [W284]. Bar buttons use `labelColor` by default [W284]. Toolbar icons render monochrome [W323, W102].
- On glass use fills, transparency and vibrancy for anything layered on top ("avoid glass on glass") [W219].
- Vibrancy levels (label, secondary, tertiary, quaternary; fill, secondary, tertiary; separator) as in HIG-Materials; avoid quaternary on thin materials [HIG-Materials].

### 2.12 Ambient colour spill on large glass

- "On larger elements, like sidebars ... Light from colorful content nearby can subtly spill onto its surface ... the light reflects, scatters, and bleeds into the shadow as well" [W219]. Sidebars "refract the content behind them — while reflecting content and the user's wallpaper from around them" [NEWS].

### 2.13 Materialize / dematerialize

- "Instead of fading, Liquid Glass objects materialize in and out by gradually modulating the light bending and lensing" [W219].
- UIKit: animating `effectView.effect = glassEffect` gives the materialize animation; `effect = nil` dematerializes; "Always prefer setting the effect property over the alpha" [W284]. Alpha < 1 on a visual effect view or its superviews makes effects "look incorrect or not show up at all" [UIK UIVisualEffectView].
- SwiftUI `GlassEffectTransition.materialize`: fades the *content* in/out and animates the glass material in/out without geometry matching; use for shapes farther apart than the container spacing [SUI, APPLY].
- **Measured timing.** From a 120 fps capture of a native nav bar: materialize ≈ **250 ms**; dematerialize ≈ **350 ms**, with the content blurring away first and the glass dissolving after it [3P-S42].
- **Reproduce.** Ramp refraction strength, blur and highlight from 0 to full (and back), fading only the content, never the glass layer's opacity [inferred].
- **Accessibility.** HIG-Accessibility: under Reduce Motion "avoid animating into and out of blurs" (replace with fades).

### 2.14 Glass container: shared sampling and droplet merging

- **API.** `GlassEffectContainer(spacing: CGFloat? = nil, content:)` (nil = system default, undocumented) [SUI]; `UIGlassContainerEffect` with `spacing` ("the distance between elements at which they begin to merge"; no documented default) [UIK].
- **Why it exists.** "Glass can not sample other glass, so having nearby glass elements in different containers will result in inconsistent behavior. Using a glass container allows these elements to share their sampling region" [W323]. One sampling pass per container improves performance [W310, APPLY]. Uniform light/dark adaptation across members [W284].
- **Merging.** "As long as there is space between them, they appear as two separate views. Only if they get closer, they start merging like small droplets of water" [W284]. "A larger spacing makes blending start sooner" [SUI]. "When animating into an overlapping frame, glass views combine into a single shape" [W284]. When container spacing > stack spacing, shapes are blended at rest [APPLY].
- **Split recipe.** Add the children at the same frame without animation, then animate them apart [W284].
- **Numbers.** Examples only: `spacing: 40.0` with 80×80 items and offset −40 [APPLY]; `spacing = 20` [W284]; badge stack spacing 16 [W323]. System default [unknown].
- **Performance.** Too many containers, or many effects outside containers, degrade performance; limit on-screen glass [APPLY]. CNN: nested glass gave "double translucency, layered blur, and unpredictable rendering"; apply glass only at the highest level; "GPU intensive, especially in scrollable or frequently updated views" [MWA208].

### 2.15 Union

- `glassEffectUnion(id:namespace:)`: all effects with the same union id, same shape and same glass variant merge into **one** shape regardless of distance; for dynamically created views or views outside one stack [SUI, APPLY]. Example: `id: item < 2 ? "1" : "2"` [code].

### 2.16 Identity morphing and transitions

- `glassEffectID(_ id:, in: Namespace.ID)` gives shapes identity so SwiftUI animates them into/out of each other [SUI]. Example: a toggle button and a stack of badges; badges emerge from the button and are "re-absorbed gracefully" [W323, Landmarks sample].
- `GlassEffectTransition`: `.matchedGeometry` (default; a shape within spacing grows out of its neighbour; with `Animation.default` it also adds scale+offset to changed content, a spring removes that), `.materialize` (2.13), `.identity` [SUI].
- Morph design intent: "a singular floating plane that the controls live on ... the controls continually shape shift" [W219]; morph inspired by "mitosis and meiosis" [MWA208].
- **Numbers.** Animation used by `withAnimation {}` default (SwiftUI default spring) [inferred]; system morph springs [unknown].

### 2.17 Shapes: capsule, fixed, concentric

- **Three shape types:** fixed (constant radius), capsule (radius = half the height), concentric ("calculate their radius by subtracting padding from the parent's") [W356].
- **Formula.** Concentric radius = container corner radius − distance between the corners, floored at an optional minimum; 0 means a square corner; uniform variants use the *largest* computed radius for all corners in the set [SUI ConcentricRectangle, Edge.Corner.Style]. UIKit: "When moving the view closer to the container's corner, its corner radius adapts automatically. When moving further away the corner radius decreases" [W284].
- **Root container.** On iPhone the root is the display's corner radius (views that reach the device's rounded corners), otherwise any view that sets `containerShape(_:)` with a `RoundedRectangularShape` (Rectangle, RoundedRectangle, UnevenRoundedRectangle, Capsule, Circle); sheets and popovers do this automatically [SUI ConcentricRectangle].
- **APIs.** `ConcentricRectangle(...)` (8 initialisers), `.rect(corners: .concentric, isUniform:)`, `Edge.Corner.Style.concentric(minimum:)` / `.fixed(_:)` [SUI]; `UICornerConfiguration.corners(radius: .containerConcentric(minimum:))`, `.capsule(maximumRadius:)`, `UIView.effectiveRadius(corner:)` [UIK]. WWDC code names `.rect(corner: .containerConcentric)`, `.fixed(8)`, `.containerRelative()` are beta names that did not ship [SUI/UIK notes].
- **Rules.** Phone layouts near a screen edge: capsule with extra margin; iPad/Mac: concentric with the window [W356]. Use concentric with a fallback minimum so a standalone component still rounds [W356]. A button at the bottom of a sheet shares the sheet's corner centre [W323]. Bars: standard items are concentric with the bar's corners and custom ones must be too [HIG-Toolbars]. Watch for "pinched" or "flared" corners [W356].
- **Doc example values** [code]: `ConcentricRectangle().padding(8.0)`, `.concentric(minimum: 12.0)`, `.fixed(24.0)`, Notes format-sheet look `ConcentricRectangle(uniformTopCorners: .fixed(24.0), uniformBottomCorners: .concentric)`, `RoundedRectangle(cornerRadius: 20)` platter.
- **Display corner radius.** Not published by Apple per device [unknown]; see §10 for measured values.

### 2.18 Corner-adapted layout regions (UIKit)

- `UIView.LayoutRegion.safeArea(cornerAdaptation:)`, `.margins(cornerAdaptation:)`, `.readableContent(cornerAdaptation:)` with `AdaptivityAxis` `.horizontal`/`.vertical`; `layoutGuide(for:)`, `edgeInsets(for:)` (26.0, no discussion) [UIK]. Insets content only along the given axis where rounded display/window corners would clip it [inferred]. W282: `.margins(cornerAdaptation: .horizontal)` for bar-like content next to iPad window controls.

### 2.19 Scroll edge effect

- **What.** Replaces bar backgrounds and hairlines. "As content begins to scroll underneath a glass element, the effect gently dissolves the content into the background, lifting the glass visually above the moving content" [W219]. "Not decorative. They don't block or darken like overlays"; only where floating UI exists [W356, HIG-ScrollViews].
- **Styles.** `ScrollEdgeEffectStyle.automatic` (default), `.soft` ("subtle, blurred"), `.hard` ("linear, nearly opaque boundary") [SUI]; UIKit `.hard` = "a hard cutoff and dividing line", "similar appearance to the standard bar backgrounds in iOS 18" [UIK, W284]. Applied at both edges in the scroll direction [SUI].
  - iOS 26: soft is the default on iOS/iPadOS; hard mostly macOS and dense UIs (Calendar), pinned column headers where the effect spans toolbar + accessory uniformly [W356, W219, W323].
  - Over dark content (glass flipped to dark) the soft effect "intelligently switches to apply a subtle dimming" [W219].
  - HIG (iOS 27 text): automatic gives a more opaque separation for top toolbars with many controls, text outside glass controls, and pinned table headers [HIG-ScrollViews].
  - **iOS 27 change.** "The `.automatic` style no longer switches between the existing soft and hard styles but provides its own visuals"; overriding to `.soft` "no longer matches the default system appearance" [W26-278]. The visible result: "a uniform toolbar appears across the top" when content scrolls under floating bars [W26-102]. macOS 27: automatic resolves to hard when free-floating text (window title) is present [W26-289].
- **Rules.** One per view; don't mix or stack soft and hard; in split views each pane may have one, equal heights [W356, HIG-ScrollViews]. Remove custom bar backgrounds/darkening [W323, W284].
- **Size.** The effect's size and shape follow the floating content above it and adapt as floating elements come and go [W310].
- **APIs.** `scrollEdgeEffectStyle(_:for:)`, `scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all)` [SUI]; `UIScrollView.topEdgeEffect/bottomEdgeEffect/leftEdgeEffect/rightEdgeEffect` with `.style` and `.isHidden` (default false) [UIK].
- **Measured (iPhone 17 sim, 26.4, y from the top of an 874-pt screen).** Under an inline title the hard band stops at the items (106 pt), not the bar edge; soft fades to about 121–122 pt; the large title rests at 116–168 [3P-S2]. Soft = "subtle variable blur effect, combined with a gradient scrim" [3P-S34]; SwiftUI content is "blurred and dimmed" [3P-S38].
- **Disagreement.** One source measured the native nav bar's default as the *hard* style on 26.5 [3P-S2 #385]; Apple (W356 "Soft is the default ... especially on iOS") and every other write-up say soft. Verify separately on large-title and inline-title screens.
- **Numbers.** Blur ramp and fade curve [unknown].

### 2.20 Edge effect shaped by custom floating controls

- UIKit `UIScrollEdgeElementContainerInteraction` (scrollView, edge): descendants such as labels, images, glass views and controls "affect the shape of the edge effect" [UIK]. SwiftUI: custom bars placed with `safeAreaBar` get the system scroll edge effect [W25 SwiftUI group lab, community transcript].
- **Reproduce.** The blur mask follows the union of the overlaying controls, not a full-width rectangle [inferred from UIK].

### 2.21 Background extension effect

- `backgroundExtensionEffect()` / `(isEnabled:)`: mirrored copies of the view placed on each edge with available safe area, blurred; the view is clipped so copies don't overlap; use sparingly; apply before `.overlay` so text/buttons aren't mirrored [SUI, Landmarks]. UIKit `UIBackgroundExtensionView` (`contentView`, `automaticallyPlacesContentView` default YES) [UIK]. Landmarks: the sidebar-width leading strip is flipped horizontally, blurred and placed under the sidebar [SUI Landmarks].
- On iPhone this matters only in split layouts/landscape; include for iPad parity.

### 2.22 Content layer: standard materials

- iOS keeps four standard materials for the content layer: ultraThin, thin, regular (default), thick [HIG-Materials]. Use these, not glass, for app backgrounds and in-content cards [HIG-Materials, W219]. Thicker = more opaque, better for fine text [HIG-Materials].

### 2.23 Content scrolls under every bar

- "The bar background is now transparent by default. Remove any background customization ... Using UIBarAppearance or backgroundColor interferes with the glass appearance" [W284]. Extend content under sidebars, toolbars and tab bars; "Don't put a solid or semi-opaque color behind controls" [HIG-Layout]. Large titles now sit at the top of the scroll content and scroll under the bar [W284]. In steady state (e.g. at launch) avoid content intersecting glass [W219].
- Colour belongs in the scroll content, so it scrolls away and bars pick it up dynamically [W26-251].

---

## 3. Navigation chrome (tab bar, sidebar, navigation bar, toolbars, search)

Third-party source ids `3P-S<n>` refer to the numbered list in §12.3. Measured iPhone values are from an
iPhone 17 Pro-class simulator (402×874 pt, display corner radius 62) on iOS 26.4/26.5 unless stated.

### 3.1 Floating tab bar (iPhone)

- **API.** `TabView { Tab(...) }` / `UITabBarController` — automatic on rebuild with the iOS 26 SDK [W102].
- **Anatomy.**
  - "Floats above content at the bottom of the screen"; items sit on a Liquid Glass background and content shows through [HIG-TabBars]. "More compact appearance" on iPhone [W256].
  - One capsule platter holding the regular tabs, plus a **separate glass circle** at the trailing end for the search tab (3.5) [W256, ADOPT, 3P-S1].
  - Labels below icons in compact width, beside them in regular width; filled symbols preferred [HIG-TabBars].
  - Selected tab sits on a tinted lens/capsule inside the platter [3P-S1, 3P-S19].
  - Badge: red oval with white text/number; for critical info [HIG-TabBars].
- **Numbers [measured].** Platter **62 pt tall**, inset **21 pt** left/right and **21 pt** above the bottom screen edge [3P-S1, S5, S8, S7 — corroborated]. Tab bar container frame 402×83; bottom safe-area inset **83 = 34 (home indicator) + 49** [3P-S3, S6]. Tab items **76×54**, inset **4** inside the platter; glyph **24 pt** [3P-S1] vs a **28 pt** drawn glyph box [3P-S62] (probably symbol size vs box); label **10 pt** [3P-S1] (11 pt per 3P-S8; unresolved). Search tab: separate **62 pt circle** with an **8 pt** gap from the tab pill [3P-S1, S62 corroborated]. Touch ID phones: same 62 bar in an 83 container, 21 above the bottom [3P-S7]. On iOS 26 the bar is always glass; an opaque `UITabBarAppearance` is overlaid with glass unless `backgroundEffect` is also nil'd [3P-S63 claimed].
- **Glass behaviour.** Small element: flips light/dark with the content behind it; glyphs flip too; monochrome by default [W219, HIG-Color]. Six Colors observed the flip depends on how long content stays under the bar (scroll speed) [3P-S20]; beta 3 Safari had a higher flip threshold [3P-S22].
- **Rules.** Navigation only, never actions; keep visible across sections; avoid a "More" overflow; don't colour labels like content backgrounds; prefer the monochrome bar over bright content [HIG-TabBars].
- **Sources.** https://developer.apple.com/design/human-interface-guidelines/tab-bars ; W256; W323; W284; 3P-S1 https://github.com/STiXzoOR/applecn.

### 3.2 Tab selection lens (press and drag across tabs)

- **What.** On touch-down/drag the selection capsule lifts into a refracting glass "droplet" that follows the finger, deforms the icons/labels under it (real-time refraction, chromatic aberration between tabs), and settles on the new tab [3P-S19, S53, S30]; NN/g: tabs "bubble and wiggle when switching views" [3P-S21]. Private class `_UILiquidLensView` [3P-S41]. **No public API** reproduces it ("draggable glass droplet tab bar" has no API — WWDC25 SwiftUI group lab) [community transcript].
- **Resting vs lifted.** Resting: semi-opaque tinted pill; lifted: full clear glass lens [3P-S41 imitation uses white 0.3 at rest].
- **Numbers.** None from Apple. Imitation values only: squash/stretch clamp ±0.3 over a 0.3 s velocity window; lift spring 0.4 s / damping 0.7; drop 0.5 s / damping 0.8 [3P-S41 IMITATION].
- **Minimized-state gesture.** You can press-and-hold the minimized tab and swipe to switch sections [3P-S19].

### 3.3 Tab bar minimize on scroll

- **API.** SwiftUI `tabBarMinimizeBehavior(_:)` with `TabBarMinimizeBehavior.automatic | .never | .onScrollDown | .onScrollUp` (iOS 26.0) [SUI]; UIKit `UITabBarController.tabBarMinimizeBehavior` (default `.automatic`) with the same cases [UIK].
- **Behaviour [stated].** "The tab bar minimizes when scrolling down, and expands when scrolling back up" (`onScrollDown`); `onScrollUp` is "Recommended if the scroll view content is aligned to the bottom" [UIK]. Triggers as soon as scrolling *starts* in the direction [SUI]. iPhone only [SUI]. "Tab bars shrink to bring focus to the content ... The moment users scroll back up, tab bars fluidly expand" [NEWS]. Tapping a tab or scrolling back to the top also restores it [HIG-TabBars].
- **Minimized anatomy.** Only the current tab remains, as a small circular glass button at the leading side; the search circle stays at the trailing side; an accessory docks inline between them [3P-S19, HIG-TabBars].
- **Measured [3P-S3].** `.automatic` does **not** minimize on iPhone [3P-S57]; `setContentOffset` does not trigger it, only a user drag does; `tabBar.frame` stays 402×83 in both states; it tracks one scroll view (the content scroll view) and not a scroll view nested in a horizontal pager.
- **Numbers.** Minimized circle diameter [unknown]; by arithmetic the inline accessory width drops 360 → 234, leaving 126 pt for two circles and two gaps [inferred from 3P-S3, S1].
- **Sources.** https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior ; https://developer.apple.com/documentation/uikit/uitabbarcontroller/minimizebehavior ; NEWS.

### 3.4 Tab bar bottom accessory

- **API.** `tabViewBottomAccessory { }` (26.0) and `tabViewBottomAccessory(isEnabled:content:)` (26.1); environment `tabViewBottomAccessoryPlacement: TabViewBottomAccessoryPlacement?` = `.expanded | .inline` (nil = undefined) [SUI]. UIKit `UITabAccessory(contentView:)`, `bottomAccessory`, `setBottomAccessory(_:animated:)`, trait `UITabAccessory.Environment` = `.regular | .inline | .none | .unspecified` [UIK].
- **Behaviour [stated].** Sits above the tab bar; "When the tab bar is minimized, the accessory view animates down to display inline with the tab bar"; inline has less room, so adapt the content (compact playback controls vs full) [W284, W323, SUI]. For persistent features (Music mini player), never screen-specific actions such as checkout [W356].
- **Numbers [measured].** 360×48 regular, 234×48 inline on a 402-pt-wide phone [3P-S3]; on iPad regular width capped at 420×48 [3P-S18, 27.1]. With `setTabBarHidden(true)` the accessory moves down and does not follow the bar off-screen [3P-S3].
- **Glass.** Its own glass capsule, concentric with the tab bar platter [inferred]. Music lets you swipe the mini player left/right (26.1) [3P press].

### 3.5 Search tab

- **API.** `Tab(role: .search)`; `tabViewSearchActivation(.searchTabSelection)` (26.0) to focus the field on selection; UIKit `UISearchTab.automaticallyActivatesSearch` (26.0, default NO; when YES, cancelling returns to the previous tab) [SUI, UIK].
- **Behaviour [stated].** "The Search tab now appears separated from the rest of the tabs in the tab bar and morphs into the search field" [W256]; "When someone selects this tab, a search field takes the place of the tab bar, and the content of the tab is shown" [W323]. The system separates it to the trailing end [ADOPT].
- **iOS 27 terminology [HIG-SearchFields, W26-292].** Two styles: **standard tab** (looks like other tabs; opens a landing page with the field at the top) and **button appearance / prominent tab** (separate button; tapping focuses the field and raises the keyboard immediately; transient, returns to the previous tab on exit).
- **Anatomy [measured].** 62 pt glass circle, magnifier glyph [3P-S1].
- **Motion.** Circle stretches into a full-width capsule field (above the keyboard when focused) while the tab capsule shrinks/collapses — a glass morph, not a cross-fade [W256; inferred geometry].
- **Observed side effect.** Health: the tab bar collapses whenever the search box is expanded [3P-S21].

### 3.6 Prominent tab (iOS 27)

- **API.** `Tab(role: .prominent)` (iOS 27.0): one tab only; if none is prominent, a `.search` tab may get the treatment by default [SUI TabRole.prominent]. "Displayed on the bottom trailing edge of the screen, distinguishing it from the other tabs" [W26-269]. It is still a tab, not a floating action button [3P-Unagar].
- **Anatomy.** Separate trailing glass circle like the search tab [inferred from W26-269 and the search-tab rendering].

### 3.7 Tab badges

- `.badge(_:)` on the tab; styling the Text has no effect inside TabView [SUI]. Red oval, white text [HIG-TabBars].

### 3.8 iPad tab bar and sidebar-adaptable morph (for completeness)

- iPad tab bar sits at the top, can share the row with the toolbar; `TabViewStyle.sidebarAdaptable` converts to a sidebar with a button; ≤5 default tabs [HIG-TabBars]. "The sidebar fluidly morphs ... into a tab bar" and back, also on rotation [W208]. "The sidebar and tab bar ... a single navigational element that fluidly scales" [W219].

### 3.9 Sidebar and inspector

- **Anatomy.** Floating inset glass sidebar above content [W356, W323]; sidebar glass more opaque than bar glass [HIG-Color]; picks up ambient colour and wallpaper [W219, NEWS]; icons use the accent colour [HIG-Sidebars, 2026-06-08]. Inspector: "edge-to-edge application of Liquid Glass" [W102, W310].
- **Behaviour.** Content extends beneath: horizontal scroll views scroll under it by default; images use background extension (2.21) [W356, HIG-Sidebars].
- **iOS 27.** "Sidebars expand to the edges on Mac and iPad"; icons regain accent colour [W26-102].

### 3.10 Navigation bar (top toolbar)

- **API.** `NavigationStack` + `.toolbar {}` / `UINavigationController` / `UINavigationBar`.
- **Anatomy.**
  - Transparent bar; no background, no hairline; items float on glass; a scroll edge effect replaces the background [W284, HIG-Toolbars].
  - Positions: leading (back, sidebar toggle, title when leading, document menu), centre, trailing (primary action, More menu, search) [HIG-Toolbars].
  - Symbols monochrome (`labelColor`), no bordered/outlined-circle symbols [HIG-Toolbars, W284].
- **Numbers [measured].** Bar row **54 pt** (was 44), glass item platters **44 pt** tall at the top of the row with **10 pt** bottom padding; large title adds **52 pt** below; title 17 semibold, large title 34 bold [3P-S1, S2 corroborated]. Glass pill width = **label width + 12 pt** at a fixed 44 height; a glyph item stays a circle while the label is ≤ 32 wide [3P-S4, device]. A glyph platter beside a back chevron measured 59 wide (oval) [3P-S3]. Hit region is the glyph, although the pill highlights on touch-down anywhere inside (visible only on a device) [3P-S4].
- **Rules.** Titles under 15 characters; at most three groups; one primary action trailing [HIG-Toolbars].

### 3.11 Back button

- Standard back and close buttons with standard symbols, not text labels [HIG-Toolbars]. The breadcrumb label next to the chevron is gone [3P-S21]. Back chevron sits in a 44 pt glass circle [3P-S3, S1]. On push, a leading bar item can morph into the back button [3P-S36].

### 3.12 Titles: large title, inline title, subtitle

- Large title by default, turns inline once scrolling starts, back to large at the top [HIG-Toolbars]. "Large titles are now placed at the top of the content scroll view, and scroll with the content underneath the bar"; extend the scroll view fully under the bar [W284].
- Subtitle: `navigationSubtitle(_:)` (new on iOS/iPadOS 26), placements `.largeTitle`, `.largeSubtitle`, `.subtitle` (26.0) [SUI]; UIKit `subtitle`, `attributedSubtitle`, `subtitleView`, `largeTitle`, `largeSubtitle`, `largeSubtitleView` (e.g. a filter button) [UIK, W284].
- iOS 27.2 beta: `titleAlignment` automatic/center/leading [UIK].

### 3.13 Toolbar item grouping on shared glass

- **Rule [stated].** "The system automatically separates them into visual groups of items. Each group shares a glass background." Image buttons share one capsule; "Text buttons, the system 'Done' and 'Close' buttons, and prominent style buttons have separate glass backgrounds" [W284]. Don't put a text action next to a symbol action in one group (reads as one button); put fixed space between text buttons [HIG-Toolbars, W356]. Custom items are grouped separately from the system back button [W323].
- **SwiftUI.** `ToolbarItemGroup` = one capsule; `ToolbarSpacer(_ sizing: SpacerSizing = .flexible, placement: = .automatic)`; `.fixed` splits capsules, `.flexible` pushes groups apart; `.sharedBackgroundVisibility(.hidden)` removes the glass from one item and puts it in its own group (e.g. avatar) [SUI, W323]. Hide whole items with `ToolbarContent.hidden(_:)`, not the inner view [ADOPT].
- **UIKit.** `UIBarButtonItem.sharesBackground` (default YES), `hidesSharedBackground` (default NO; both ignored inside a multi-item `UIBarButtonItemGroup`); `UIBarButtonItem.fixedSpace()` = zero-width item that splits the shared background (26.0); `UIBarButtonItemGroup.fixedSpace()`; by default **each flexibleSpace separates backgrounds**, set `flexibleSpace.hidesSharedBackground = false` to spread items evenly inside one capsule [UIK, W284].
- **Numbers.** Gap between separate capsules [unknown]; fixed-spacer width is system-chosen [SUI SpacerSizing]; group platter height 44 [3P-S1].
- **Example layout [code].** Landmarks: Share | fixed | [Favorite + Collections] | fixed | Info [SUI Landmarks]. Mail bottom bar: filter, flexible, [search, fixed, compose] [W323].

### 3.14 Prominent toolbar action

- `ToolbarItem(placement: .confirmationAction)` renders as `.glassProminent` automatically [3P-S31, S43]; explicit `.buttonStyle(.glassProminent)` / `borderedProminent().tint(...)` [W256]; UIKit `UIBarButtonItem.Style.prominent` (26.0; `.done` deprecated and renamed) — never grouped with other items, "other styling changes appropriate to their context" [UIK].
- Anatomy: accent-tinted glass; on iOS the Done action is "often as a blue checkmark" [W356], a filled **44 pt circle** with a checkmark [3P-S1, S19].
- UIKit `tintColor` on a plain item colours only the symbol; `.prominent` tints the background [W284].

### 3.15 Bottom toolbar

- `.toolbar { ToolbarItem(placement: .bottomBar) }` / `UIToolbar` via `toolbarItems`. Floating glass groups over content; a `.bottomBar` item switches on the bottom scroll edge effect, `.safeAreaInset(edge: .bottom)` does not [3P-S36].
- **Numbers [measured].** 44 pt items in glass platters with 4 pt padding (platter 52 tall); prominent action a filled circle [3P-S1]. Toolbar frames read unreliably in UIKit; use keyboard layout guide/safe areas [3P forum].

### 3.16 Toolbar morph across push/pop

- "During navigation transitions, these items can even morph" [W256]; "fluid morphing of the toolbar as users navigate and scroll" [W102]. UIKit matches items by position/content heuristics or an explicit `UIBarButtonItem.identifier` (26.0) [UIK]. SwiftUI: stable `ToolbarItem(id:)` avoids odd animations [3P-S43]. Transitions are "fluid and interruptible" [W243].

### 3.17 Bar button badges

- SwiftUI `.badge(count)` on the toolbar button's content [W323]; UIKit `UIBarButtonItem.badge` = `.count(_)`, `.string(_)`, `.indicator()`, with `backgroundColor`, `foregroundColor`, `font` (26.0; defaults undocumented) [UIK].

### 3.18 Navigation bar minimization (iOS 27)

- SwiftUI `toolbarMinimizationBehavior(_:for:)` with `ToolbarMinimizationBehavior.automatic | .never | .onScrollDown | .onScrollUp`, only `.navigationBar`; `toolbarMinimizationSafeAreaAdjustment` (`.disabled` keeps content in place for full-bleed media); `toolbarMinimizationRestoration` (27.0) [SUI]. By default the nav bar minimizes when `searchable` uses `toolbarPrincipal` [SUI]. UIKit `UINavigationItem.navigationBarMinimization: UIBarMinimization` with behaviour, restoration (`automatic`, `atScrollEdge`) and safe-area adjustment [UIK]. (The WWDC26 demo spelled it `toolbarMinimizeBehavior`; shipped name is `toolbarMinimizationBehavior` [SUI].)

### 3.19 iOS 27 toolbar overflow, priority, pinning and padding

- `ToolbarOverflowMenu { }` (always overflow; the nav bar's `•••`), `.visibilityPriority(.high/.low)` (lower priority overflows first), `ToolbarItemPlacement.topBarPinnedTrailing` (overflows only when search is active and space runs out), `ToolbarContent.contentMarginsRemoved()` (drop item padding but keep glass) [SUI, W26-269, W26-8120]. UIKit `visibilityPriority`, `isPaddingRemoved` [UIK]. iOS 26 already swept groups that didn't fit into a `•••` [3P-S3].

### 3.20 Search field placement (iPhone)

- **Placement.** `searchable` on a NavigationStack/SplitView goes to the **bottom** on iPhone, top-trailing on iPad [W323, W256]. The field is on its own glass surface; tapping activates it and shows the keyboard [W323]. By default the search item is the **leading-most** item in the bottom bar; reposition with `DefaultToolbarItem(kind: .search, placement: .bottomBar)` [SUI]. UIKit `preferredSearchBarPlacement = .integrated | .integratedButton | .integratedCentered`, `searchBarPlacementAllowsToolbarIntegration` (default true), `searchBarPlacementBarButtonItem` in `toolbarItems` (otherwise trailing-most) [UIK].
- **Minimized.** `searchToolbarBehavior(.minimize)` (doc example typo `.minimized`) shows a button-like control; tapping it gives "a full-width search field appears above the keyboard" (Mail) [SUI, W323]. `integratedButton` = always a button [UIK]. Use the button form when there are more than two other toolbar items [W26-292].
- **Keyboard.** "When search is placed in the bottom Toolbar, the field elegantly animates up over keyboard"; top-toolbar search also pulls the field up over the keyboard [W26-292, HIG-SearchFields]. Field slides up with the keyboard [ADOPT].
- **Numbers [measured].** Field is a **44 pt capsule**; magnifier at x=12, text at x=39 [3P-S1].
- **Guidance.** Bottom when there is room; top when bottom content matters (Wallet) or no bottom toolbar [HIG-SearchFields].

### 3.21 Scope bars and tokens

- Scope bar sits in the results area, defaults to the broader scope; tokens are selectable search terms paired with suggestions [HIG-SearchFields, W26-292]. No glass-specific styling documented [unknown].

---

## 4. Presentations (sheets, popovers, menus, alerts, transitions)

The shared rule: **presentations emanate from, and morph out of, the glass control that triggered them**,
and collapse back into it on dismiss. "Like sheets, other presentations such as menus, alerts, and
popovers flow smoothly out of liquid glass controls, drawing focus from their action to the
presentation's content" [W323]. "When a presentation, like a menu or a popover is originated from a
glass button, the button morphs into the overlay" [W284].

### 4.1 Sheets

- **API.** `.sheet` + `presentationDetents([.height(h), .fraction(f), .medium, .large])` (default large only) [SUI]; `UISheetPresentationController` with `detents`, `Detent.backgroundEffect` (26.1) [UIK]. Don't set `presentationBackground` or custom sheet backgrounds, or the glass is lost [W323, ADOPT, 3P-S9].
- **Anatomy by detent [stated].**
  - "On iOS 26, partial height sheets are inset by default with a Liquid Glass background." "At smaller heights, the bottom edges pull in, nesting in the curved edges of the display." [W323]
  - "When transitioning to a full height sheet, the glass background gradually transitions, becoming opaque and anchoring to the edge of the screen." [W323]
  - "When focus shifts, like dragging a sheet upward, Liquid Glass subtly recedes, becoming more opaque and gently growing in size" [W356].
  - "Sheets feature an increased corner radius, and half sheets are inset from the edge of the display to allow content to peek through" [ADOPT].
  - Sheets are concentric containers; content inside can use concentric shapes (a bottom button shares the sheet's corner centre) [SUI ConcentricRectangle, W323].
- **Anatomy by detent [measured/observed].**
  - Inset is **not constant**: lowest detent has a visible gap and fully rounded corners; mid detent is closer to the edges with the corner radius adjusting; top detent has no gap [3P-S13]. Apple Maps sheet floats **≈8 pt** from the left, right and bottom edges, bottom corners = display radius − 8 (e.g. 62 − 8 = 54 on a 62-radius phone) [3P-S14]. One view-tree dump reports full width at the medium detent (likely the controller frame, not the drawn glass) — verify [3P-S1].
  - Top corners follow the display corner radius (62 on 402×874, 55 on 393×852) [3P-S9, S13, S14, S1, S15].
  - Grabber **36×5** [3P-S1].
  - The floating sheet's glass is **interactive**: touching/dragging draws a specular flare that tracks the finger (more visible in dark mode); it stops once the sheet is past about **0.9** of screen height, where it becomes a regular opaque sheet [3P-S16, S17 corroborated].
- **Tab bar interplay.** Sheets slide under the floating tab bar by default; the small detent extends behind the tab bar; the corner "morph" between detents comes from `.concentric(minimum:)` against the screen radius [3P-S63 claimed, wix RNN maintainers].
- **Dimming / modality.** "When a task interrupts the main flow, pair Liquid Glass with a dimming layer"; parallel tasks use glass without dimming [W356]. UIKit: `largestUndimmedDetentIdentifier` nil = dim at all detents; set to medium to dim only at large; undimmed area stays interactive [UIK]. SwiftUI `presentationBackgroundInteraction(.enabled(upThrough:))` [SUI]. Scrim opacity [unknown] — 0.4 and 54% circulate but neither is measured [3P-S1, S42].
- **Content gotchas.** A `Form`/`List` in a sheet paints an opaque background over the glass (`.scrollContentBackground(.hidden)`); pushed NavigationStack destinations add an opaque layer (`containerBackground(.clear, for: .navigation)`) [3P-S10].
- **HIG layout rules.** Cancel leading / Done trailing (2026-03-24 update); multi-step sheets swap Cancel for Back; grabber shown when there are multiple detents; swipe down to dismiss with confirmation for unsaved changes; one sheet at a time [HIG-Sheets, MWA201].
- **Numbers.** Sheet corner radius = display corner radius [measured]; floating inset ≈8 [observed, one source]; floating→opaque threshold ≈0.9 height [observed]; detent example `.height(180)` [code]. Opacity ramp curve [unknown].
- **Sources.** W323; W356; ADOPT; https://nilcoalescing.com/blog/PresentingLiquidGlassSheetsInSwiftUI/ ; https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets.

### 4.2 Sheet grabber, detent interaction

- `presentationDragIndicator` / `prefersGrabberVisible`; tapping the grabber cycles detents; dragging resizes; VoiceOver-accessible [HIG-Sheets]. Medium ≈ half the screen, inactive in compact height; large = full height [UIK].

### 4.3 Sheet zooms out of its source button

- **API.** SwiftUI `ToolbarContent.matchedTransitionSource(id:in:)` (26.0) on the toolbar item + `.navigationTransition(.zoom(sourceID:in:))` on the sheet content [SUI, W323]. UIKit `viewController.preferredTransition = .zoom { _ in barButtonItem }` / `.zoom(options:sourceBarButtonItemProvider:)` (26.0) [UIK, W284].
- **Behaviour.** The glass button expands into the sheet and the sheet collapses back into the button on dismiss; corner radius interpolates [SUI matchedTransitionSource configuration interpolates modifiers].
- **Measured dismiss gesture (zoom-presented sheets only).** Shrink pivots at the grabbed point; scale gain 0.64 per card height dragged; 1:1 until 0.48 of card height, then rubber-bands toward a 0.33 scale floor [3P-S42 MEASURED via iPhone Mirroring].

### 4.4 Cross-fade sheet (iOS 27)

- `NavigationTransition.crossFade` (27.0): the sheet fades in over content instead of sliding up [SUI].

### 4.5 Popovers

- **Behaviour.** "In iOS 26 and later, the popover animates from and replaces the specified item until someone selects an action item or dismisses the popover" (sourceItem = bar button item) [UIK sourceItem]. Automatic for toolbar popovers [W102]. Regular glass, text-heavy [HIG-Materials]. Don't add visual-effect views inside popovers [ADOPT]. Popovers are concentric containers [SUI].
- **Anatomy.** Morphing from the button means no classic arrow when sourced from a glass bar item [inferred from "replaces the specified item"]. HIG still says point the arrow at the source for arrowed popovers, animate size changes, one at a time, avoid in compact width [HIG-Popovers].
- **Numbers.** Radius 26 / arrow 13×6.5 appear only in an unverified web kit [3P-S1]; [unknown].

### 4.6 Menus and pull-down buttons

- **Behaviour [stated].** "When showing a menu, the bubble simply pops open to reveal the content contained within ... keeps everything right where you just tapped" [W219]. "Menus get this behavior automatically" (button morphs into the overlay) [W284]. Larger glass during the morph "simulate[s] a thicker, more substantial material ... deeper, richer shadows ... more pronounced lensing and refraction ... softer scattering of light" [W219]. Menus are large elements: they adapt but **do not flip** light/dark [W219].
- **Anatomy.** Leading icons consistently; use one symbol to introduce a group of related actions [W323, W356]. iOS layouts: small (top row of 4 icon-only items), medium (top row of 3 icon+label items), large (plain list, default) [HIG-Menus]. Separators may be a short gap in the menu background [HIG-Menus]. iPad/Mac menu bars show a minimal set of icons by default in the 27 releases (`preferredImageVisibility`, `.labelStyle(.titleAndIcon)`) [W26-278, W26-269].
- **Observed.** "The content area is no longer blurred around menus" [3P-S19]. Morph bugs by version: 26.0–26.0.1 circle-shaped glass morphs as a rectangle then snaps; 26.1 a Menu inside a GlassEffectContainer breaks the morph [3P-S35].
- **Numbers.** No measured geometry [unknown]; a web kit's approx. width 250, item 44, radius 26 is unverified [3P-S1]. Imitation spring stiffness 120 / damping 16 [3P-S42 CLAIMED].

### 4.7 Context menus

- HIG (2022–23 text): the system lifts a preview out of the content and **dims the screen behind** the preview and menu; match the preview clipping to its shape; the menu may open above or below, reverse item order to keep frequent items near the finger [HIG-ContextMenus].
- **Observed iOS 26 change.** Messages long-press "no longer dims or blurs the rest of the thread" [3P-S52]; MacStories: content no longer blurred around menus [3P-S19]. Whether a dim remains elsewhere [unknown] — verify per app.
- Menu surface is large glass (thick, non-flipping) [W219].

### 4.8 Edit menus

- Compact horizontal style for touch, vertical for keyboard/pointer; positioned above/below the selection with a pointer [HIG-EditMenus]. iOS 26: overflow opens a full secondary menu instead of scrolling sideways [3P-S19].

### 4.9 Alerts

- **API.** `.alert` / `UIAlertController(style: .alert)`. No new API [UIK].
- **Anatomy.** Regular glass card [HIG-Materials, W243]. Typography "bolder and left-aligned to improve readability in key moments like alerts" [W356]. Up to 3 buttons; default button trailing in a row / top of a stack; Cancel leading / bottom; titles ≤ 2 lines [HIG-Alerts].
- **Numbers [measured, 26.5].** **320 wide, radius 34**, glass; title 17 semibold, message 13, both left-aligned, **24 pt** side padding; actions **48 pt capsules** on a fill inside a **16 pt** inset, **8 pt** apart; two side by side, three or more stacked; preferred action semibold [3P-S1]. Left alignment corroborated [3P-S59].
- **Motion.** Alerts flow out of the control that presented them when attached to one [W323]; standalone alerts appear centred [3P-S1].

### 4.10 Action sheets and confirmation dialogs

- **Behaviour [stated].** "It used to appear at the bottom of the screen ... Now, it springs from the action itself" [W356]. "Starting in iOS 26, they behave the same on iPhone, appearing directly over the originating view"; "Action sheets presented inline don't have a cancel button because the cancel action is implicit by tapping anywhere else" [W284]. People can keep interacting with the rest of the UI [SUI notes on ADOPT]. Requires a source: `confirmationDialog` attached to the button / `popoverPresentationController?.sourceItem` [ADOPT, W284]. Dialogs "automatically morph out of the buttons that present them" [W323].
- **Anatomy [measured].** Same card as the alert (320 × r34) anchored to its source, or centred without one; 48 pt capsules 8 apart; destructive red; Cancel a bolder capsule at the bottom when present [3P-S1].
- **HIG.** Cancel at the bottom; destructive at the top; one-line title [HIG-ActionSheets].
- **iOS 27.** `.confirmationDialog(_:item:)` binding variant [W26-269].

### 4.11 Push navigation zoom and interruptible transitions

- `navigationTransition(.zoom(sourceID:in:))` + `matchedTransitionSource(id:in:configuration:)` (iOS 18; the configuration closure's modifiers, e.g. `cornerRadius(8)`, interpolate) [SUI]. Navigation transitions "are now fluid and interruptible" — users can interact before the animation finishes [W243].

---

## 5. Controls

Governing rule: controls in the **content layer** stay solid at rest and **lift into glass only while
touched** — "Elements can even lift up into Liquid Glass temporarily, such as when you interact with a
component ... the transparent liquid lens can be seen through to precisely observe the value underneath
it" [W219]. "Controls like toggles, segmented pickers, and sliders now transform into liquid glass during
interaction" [W323]. Capsule geometry "in the mirrored proportions of sliders and switches" [W356].
"Sizes are updated slightly for controls like UISwitch" [W284].

### 5.1 Glass button

- **API.** `.buttonStyle(.glass)` (≈ `bordered`), `.buttonStyle(.glass(_ glass: Glass))` e.g. `.glass(.clear)`; `GlassButtonStyle.init(_:)` is 26.1 [SUI]. UIKit `UIButton.Configuration.glass()` [UIK].
- **Anatomy.** Capsule by default (bordered buttons are capsules on iOS 26) [W323]; vibrant monochrome label; regular glass [SUI, W323].
- **Interaction.** Interactive glass response (2.5): scale up, bounce, shimmer, touch-point glow [W323, W284]. 26.0 bug: standalone circular glass buttons widened to a capsule when tapped; fixed in 26.1 beta 2 [3P-S37].
- **Don't** apply raw `glassEffect` to a Button ("a button sitting on glass, which won't look right"); use the glass button styles + `buttonBorderShape` [W26-8120].
- **Numbers [measured].** Sizes: mini/small **28**, medium **34**, large **50** pt tall capsules; icon-only glass circle **34**; label 15/17 pt [3P-S1]. Press scale [unknown] (1.1 in circulation is from sample code, not a capture) [3P]; press brightening ≈ **+15 luma** in light mode, lift over **150 ms**, collapse in **60 ms** [3P-S42 MEASURED light only].

### 5.2 Prominent glass button

- `.buttonStyle(.glassProminent)` (≈ `borderedProminent`; no custom-Glass init) [SUI]; `UIButton.Configuration.prominentGlass()` tints the glass with the tint colour [UIK, W284]. Accent colour fills the background, label white [HIG-Buttons, HIG-Color]. One or two per view [HIG-Buttons]. `.glassProminent` + `.circle` showed artefacts in beta, fixed with `.clipShape(Circle())` [3P-S43].

### 5.3 Clear glass buttons

- `UIButton.Configuration.clearGlass()`, `.prominentClearGlass()`; SwiftUI `.glass(.clear)` [UIK, SUI]. Needs a dimming layer when over bright media (2.2).

### 5.4 Button shapes and sizes

- `buttonBorderShape(.automatic | .capsule | .circle | .roundedRectangle | .roundedRectangle(radius:))` — no new cases [SUI]. Icon-only → circle; text-only → rounded rectangle or capsule; icon+text → capsule; rounded rectangles in vertical stacks, capsules in rows [HIG-Buttons, visionOS guidance applied to iOS glass].
- `controlSize(.extraLarge)`: "For your most important, prominent actions there is now support for extra large sized buttons" [W323]; the SUI page still says it resolves to `.large` off visionOS (stale) — measure [SUI]. UIKit has no `extraLarge` button size (`large/medium/small/mini`) [UIK].
- `UIButton.Configuration.cornerStyle` `.capsule` etc. unchanged [UIK].
- Hit target ≥ 44×44 pt (minimum 28×28) [HIG-Buttons, HIG-Accessibility].

### 5.5 Toggle / switch

- **Behaviour.** At rest a solid white knob; while pressed or dragged the knob turns into a glass lens (`_UILiquidLensView`) that stretches and lets you see the track through it [W323, W284, 3P-S1].
- **Numbers [measured].** Track **63×28** (r14); knob **37×24** oval, inset **2**, travel **22**; off track `tertiaryLabel`-like fill, on track system green; knob thumb shadow [3P-S1 26.5]. Knob size while dragged: 58×38.3 (≈1.57×) vs 1.25× in two imitations — [unknown] [3P-S41, S42]. Switch thumb "a wider oval" on 26.3 (unverified) [3P].
- **HIG.** Switch style only in list rows; default green; accent colour allowed if contrast holds [HIG-Toggles].

### 5.6 Slider

- **API.** SwiftUI `Slider(value:in:neutralValue:enabledBounds:label:currentValueLabel:minimumValueLabel:maximumValueLabel:ticks:onEditingChanged:)` with `SliderTick`, `SliderTickBuilder` (26.0; not tvOS); `sliderThumbVisibility(.hidden)` [SUI]. Ticks appear automatically when `step` is given [W323]. UIKit `sliderStyle = .default | .thumbless`, `trackConfiguration = UISlider.TrackConfiguration(allowsTickValuesOnly:neutralValue:enabledRange:numberOfTicks:)` / `ticks: [Tick(position:title:image:)]` [UIK].
- **Behaviour [stated].** Thumb becomes glass on grab; "they now preserve momentum and stretch when they are moved" [W284]; momentum "just like scrolling" [3P-S19]. Fill grows from `neutralValue` (e.g. centre), not from the minimum [W323, W284]. Thumbless style looks like a progress bar when not interactive (media) [W284].
- **Numbers [measured].** Track **6** (r3), fill = tint; thumb **37×24** white oval; overall height **34** [3P-S1]. Example values [code]: ticks at 60% and 90% [W323]; `neutralValue: 0.2`, `numberOfTicks: 5` [W284].
- **Imitation physics (for calibration only).** Thumb glide spring 0.5 s / damping 1.0; release 0.3 s / 0.8; rubber-band at ends with haptics [3P-S41].

### 5.7 Segmented control

- **Behaviour.** Selection indicator lifts into a glass lens on touch-down/drag, "the same bubbly, interactive glass effect on touch down that tab bars have" [W284, W323, 3P-S53].
- **Numbers [measured].** **32 pt** capsule (r16) on `tertiarySystemFill`; selected white capsule inset **2** (28 tall) with a soft shadow; labels 13 medium, semibold when selected [3P-S1].
- **HIG.** ≤ 5 segments on iPhone; equal widths; text or images, not mixed [HIG-SegmentedControls].

### 5.8 Stepper

- **Numbers [measured].** **94×32** capsule on the fill, ± glyphs, short centre divider [3P-S1]. No glass behaviour documented [HIG-Steppers, UIK].

### 5.9 Pickers

- Menu-style pickers morph from their button like menus (4.6) [inferred from W284 "Menus get this behavior automatically"]. Date picker styles compact (value in accent colour, opens a calendar), inline, wheels [HIG-Pickers]. No glass-specific docs [HIG-Pickers].

### 5.10 Page control

- Translucent rounded-rectangle platter behind the dots: `automatic` (shown while interacting), `prominent` (always), `minimal` (never) [HIG-PageControls]. Dots **7 pt** at **17.7 pt** pitch [3P-S1]. Observed: carousel dots "morph into the word Search after a few seconds" in some system apps [3P-S21].

### 5.11 Text fields and search fields

- Search field: glass capsule 44 tall in bars (3.20). Text field `roundedRect` **34** tall, radius **5** [3P-S1]. No glass on plain text fields [HIG-TextFields].

### 5.12 Lists and forms

- "Taller rows and more padding", section corners rounder to match controls, **section headers title case, no longer all caps**; use `FormStyle.grouped` [ADOPT]. Grouped table corners echo capsule geometry [W356].
- **Numbers [measured].** Inset grouped: side inset **20** (16 on ≤375-pt-wide phones), corners **26**, rows **52**, subtitle rows 73 [3P-S1].
- Most table views no longer pin the title bar; they rely on the edge blur [3P-S19].

### 5.13 Progress

- Thumbless slider as a playback progress bar [W284]. Progress bar 4 pt; activity indicator 20/37 [3P-S1].

### 5.14 Swipe actions

- No Apple glass documentation for swipe actions [unknown]. iOS 27 adds `onPresentationChanged:` to `swipeActions` and `swipeActionsContainer()` [SUI 27 via 3P-Crosley].

### 5.15 iPad pointer hover platter

- Hover highlight is "a liquid glass platter" that materializes on the hovered button and "bends and refracts its underlying elements"; it catches up with the pointer; no magnetism, 1:1 tracking [W208]. Not needed on iPhone.

### 5.16 System keyboard and system sheets

- The keyboard is glass with **rounded top corners**, under which the app's background shows; apps only choose a light/dark keyboard background [3P-S66 forum]; key presses flash bright highlights (toned down by 26.4 Reduce Bright Effects) [3P-S29]. Keyboard corner radius [unknown].
- The keyboard, share sheet and other system UI are Liquid Glass and cannot be opted out of when building with the iOS 27 SDK [UIK UIDesignRequiresCompatibility]. Beta 3 darkened the keyboard's search bar [3P-S22]. A Flutter app shows the real keyboard, so its own glass must sit convincingly next to it [inferred].

---

## 6. System surfaces an app touches

### 6.1 App icon appearances

- Layered icons (background + 1–4 foreground groups; "two to four layers is the sweet spot") pick up specular highlights, refraction, translucency and frost that adapt with size; supply square unmasked 1024×1024 layers (1088 on watch); don't bake in highlights, shadows, bevels or glows [HIG-AppIcons, W220, W361, W102].
- Appearances: **default, dark, clear light, clear dark, tinted light, tinted dark** [HIG-AppIcons]. Icon Composer per-group knobs: specular on/off, shadow neutral/chromatic, blur/translucency, opacity, blend mode, fill [W361].
- Gyro-driven edge light on icons [W220]; highlights at top-left and bottom-right corners produce a tilt illusion [3P-S51].
- **iOS 27.** Icons render "sharper and more defined"; new selective "refraction" feature; Icon Composer builds icons from multiple layers of Liquid Glass with annotation tools [W26-102].

### 6.2 Widgets clear/tinted

- Home Screen widget appearances light, dark, **clear** (desaturated, translucency, highlights, Liquid Glass material), **tinted** [HIG-Widgets]. Accented rendering mode tints content white and replaces the background with themed glass or a tinted colour; partially transparent content keeps its opacity [W278]. APIs `@Environment(\.widgetRenderingMode)`, `widgetAccentedRenderingMode(.desaturated | .accented | .accentedDesaturated | .fullColor)` [W278].

### 6.3 Lock Screen clock (reference only)

- Clock "crafted out of Liquid Glass" and adapts behind the photo subject [NEWS]; 26.2 adds Glass/Solid and a transparency slider for the clock [3P-S26, S27].

---

## 7. Accessibility and user settings

All system glass adapts automatically; a Flutter reproduction must read these settings and switch its
own glass the same way. Test Dark Mode with Increase Contrast and Reduce Transparency, each alone and
both together [HIG-DarkMode].

### 7.1 Reduce Transparency

- "Makes Liquid Glass frostier and obscures more of the content behind it" [W219]. Adds darker backgrounds to translucent areas (Control Center, icons, folders) [3P-S58]. Beta 2 "dialed up" its strength [3P-S24]. Flutter: `MediaQuery` has no direct flag for this on iOS [inferred; needs a platform channel — `UIAccessibility.isReduceTransparencyEnabled`]. Apple's web CSS uses a ~97% opaque fallback material (web only, not iOS) [3P-S1].

### 7.2 Increase Contrast

- "Makes elements predominantly black or white and highlights them with a contrasting border" [W219]. Keeps some translucency but removes softness and adds a visible border [3P search summary]. Every custom colour needs increased-contrast light/dark variants [HIG-Color]. Contrast ≥ 4.5:1 for text ≤ 17 pt, 3:1 for ≥ 18 pt or bold [HIG-Accessibility].

### 7.3 Reduce Motion

- "Decreases the intensity of some effects and disables any elastic properties for the material" [W219]. HIG: cut automatic/repeating animation incl. zoom and scale, tighten springs, track gestures directly, replace x/y/z transitions with fades, "avoid animating into and out of blurs" [HIG-Accessibility]. So under Reduce Motion: no gel stretch, no bounce on press, morphs become cross-fades, materialize becomes a fade [inferred].

### 7.4 Show Borders (replaced Button Shapes)

- Settings > Accessibility > Display & Text Size > Show Borders: draws a border around many low-contrast glass elements; back button "drops Liquid Glass shine for a proper border"; gray circles behind arrows [3P-OSXDaily, 3P-iDownloadBlog]. macOS 27 gained the same "show borders" environment value "just like iOS" [W26-102]. SwiftUI reads the old Button Shapes flag via `accessibilityShowButtonShapes` [3P-NilCoalescing 2022; mapping to Show Borders inferred].

### 7.5 Liquid Glass Clear/Tinted (26.1) → slider (27)

- iOS 26.1: Settings > Display & Brightness > Liquid Glass: **Clear** (default, "more transparent, revealing the content beneath") or **Tinted** ("increases the opacity of Liquid Glass and adds more contrast"); preview before committing; disabled while Reduce Transparency/Increase Contrast are on [support.apple.com iPhone guide, 3P-S25]. With Tinted, the user's light/dark choice is respected (26.4) [3P-S28]. Simulator has no Tinted option [3P-S28].
- iOS 27: continuous slider "anywhere from ultra clear to fully tinted"; system glass "automatically responds to the new Liquid Glass slider to adjust its tint" [W26-102, W26-269].
- 26.4: **Reduce Bright Effects** (Accessibility > Display & Text Size) tones down the bright flash on interaction (buttons, keyboard, Control Center, passcode) [3P-S29].
- A Flutter app cannot read these directly; plan a platform channel or accept a mismatch [3P notes].

### 7.6 Appearance and window state

- Glass has light and dark appearances following `userInterfaceStyle`, plus the independent per-element flip (2.9) [W284]. When a window loses focus (iPad/Mac) glass "visually recedes" [W219]; iPad apps dim icons/text when inactive (`@Environment(\.appearsActive)`) [W26-269].

### 7.7 Colour and type retune (non-glass but part of the look)

- System colours retuned across light, dark and increased-contrast for harmony with glass; don't hard-code values [W356, HIG-Color]. Typography "bolder and left-aligned" in alerts/onboarding [W356]; emphasized weights added to the type ramp (Large Title 34/41 bold emphasized, Body 17/22, etc.) [HIG-Typography]. Supply light and dark colours even for single-appearance apps because glass adaptivity needs both [HIG-Color].

---

## 8. iOS 27 delta (what changed after iOS 26)

| Area | iOS 27 change | Source |
|---|---|---|
| Material | "Tuned Liquid Glass so it more effectively diffuses complex content"; "a darkened edge along with brighter specular highlights"; automatic for apps, no recompile | W26-102 |
| User setting | Continuous Clear ↔ Tinted slider replaces the 26.1 two-way choice | W26-102, W26-269 |
| Top bars | "When content scrolls under floating bars, a uniform toolbar appears across the top"; automatic for standard toolbars; customise via scroll edge APIs | W26-102 |
| Scroll edge | `.automatic` "no longer switches between the existing soft and hard styles but provides its own visuals"; `.soft` no longer matches the default | W26-278 |
| Sidebars | Extend to the edges on iPad/Mac; accent-coloured icons | W26-102 |
| Tabs | `Tab(role: .prominent)`, bottom-trailing separated tab | W26-269, SUI |
| Nav bar | `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)`; `UIBarMinimization` | SUI, UIK |
| Toolbar | `ToolbarOverflowMenu`, `visibilityPriority`, `.topBarPinnedTrailing`, `contentMarginsRemoved` / `isPaddingRemoved` | SUI, UIK |
| Sheets | `NavigationTransition.crossFade` | SUI |
| Menus | iPad/Mac menu bars show minimal icons by default; `preferredImageVisibility` | W26-278 |
| Opt-out | `UIDesignRequiresCompatibility` ignored when building for iOS 27+ | UIK |
| Icons | Sharper rendering, selective refraction, multi-layer Liquid Glass in Icon Composer | W26-102 |
| macOS-only (context) | Click-bounce interactive glass; automatic scroll edge resolves hard with free-floating titles; tighter uniform window radius | W26-289, W26-102 |
| 27.1/27.2 betas | Vertical bars for a foldable ("iPhone Duo"): `axisBehavior`, `verticalBarCompressionBehavior`, `LayoutRegion.bar(onEdge:extent:)`; `titleAlignment` (27.2) | SUI, UIK |

Implication for a Flutter app in late 2026: most users are on iOS 26.x or 27; the port should
parameterise edge darkness, specular brightness, diffusion (blur), and the top-bar edge treatment so it
can match both, keyed off the OS major version [inferred].

---

## 9. Numbers ledger

### 9.1 Every number Apple itself states or shows

| Value | Meaning | Tag | Source |
|---|---|---|---|
| 35% | Dark dimming layer behind clear glass over bright content | stated | HIG-Materials |
| `.black.opacity(0.3)` | Dimming under a clear-glass label | code | SUI Glass.clear |
| height / 2 | Capsule radius | stated | W356 |
| parent radius − padding (floor at minimum, 0 = square) | Concentric radius | stated | W356, SUI Edge.Corner.Style |
| largest computed radius | Radius used for uniform corner sets | stated | SUI ConcentricRectangle |
| 44×44 pt default, 28×28 pt minimum | Hit target | stated | HIG-Accessibility, HIG-Buttons |
| 1 or 2 per view | Prominent buttons | stated | HIG-Buttons |
| 1, trailing | Primary (`.prominent`) toolbar action | stated | HIG-Toolbars |
| ≤ 3 | Toolbar groups | stated | HIG-Toolbars |
| < 15 characters | Toolbar/nav titles | stated | HIG-Toolbars |
| ≤ 5 | iPad default tabs; iPhone segments | stated | HIG-TabBars, HIG-SegmentedControls |
| ≤ 3 buttons, ≤ 2-line title | Alerts | stated | HIG-Alerts |
| 4 / 3 / list | Small / medium / large iOS menu top rows | stated | HIG-Menus |
| ≈ 10 | Max page-control dots | stated | HIG-PageControls |
| 4.5:1 / 3:1 | Text contrast (≤17 pt / ≥18 pt or bold) | stated | HIG-Accessibility |
| 17 pt default, 11 pt min | iOS text sizes | stated | HIG-Accessibility |
| 1024 px (1088 watch) | Icon canvas | stated | W220, HIG-AppIcons |
| `.height(180)` | Custom sheet detent | code | W323 |
| `spacing: 40.0`, 80×80, offset −40 | Container merge example | code | APPLY |
| `spacing = 20` | UIGlassContainerEffect example | code | W284 |
| `VStack(spacing: 16)`, `.rect(cornerRadius: 16)` | Badge stack and custom glass shape | code | W323 |
| `.fixed(8)` (shipped: `.corners(radius: 8)`) | UIKit corner example | code | W284 |
| 250×88 vs 150×44 | Larger = more opaque vs smaller = clearer flipping glass | code | W284 |
| `neutralValue: 0.2`, `numberOfTicks: 5`; ticks 60% and 90% | Slider examples | code | W284, W323 |
| `.fixedSpace(0)` | Splits a shared glass background | code | W284, UIK |
| 8, 12, 24, 240 | ConcentricRectangle doc examples (padding, minimum, fixed, frame) | code | SUI |
| 20 | `RoundedRectangle(cornerRadius: 20)` container shape example | code | SUI containerShape |
| 21 | `presentationCornerRadius(21)` doc example (pre-26 API) | code | SUI |

Nothing else numeric is published by Apple for iOS glass.

### 9.2 Third-party measured values (iPhone, points)

| Item | Value | Tag | Source |
|---|---|---|---|
| Nav bar row / item platter / bottom padding | 54 / 44 / 10 | measured, corroborated | 3P-S1, S2 |
| Large title block | +52; title 17 semibold; large 34 bold | measured | 3P-S1 |
| Glass bar pill width | label width + 12 at 44 tall; circle while label ≤ 32 | measured (device) | 3P-S4 |
| Done/confirm | filled 44 circle with checkmark | measured | 3P-S1 |
| Tab bar platter | 62 tall; inset 21 left/right/bottom | measured, corroborated | 3P-S1, S5, S8, S62 |
| Tab bar container / bottom inset | 402×83; 83 = 34 + 49 | measured | 3P-S3, S6 |
| Tab item | 76×54 inset 4; glyph 24 (box 28); label 10 (or 11) | measured, disputed | 3P-S1, S62, S8 |
| Search tab circle / gap | 62 / 8 | measured, corroborated | 3P-S1, S62 |
| Bottom accessory | 360×48 regular, 234×48 inline (402-wide phone) | measured | 3P-S3 |
| Bottom toolbar | 44 items, 4 padding, 52 platter | measured | 3P-S1 |
| Search field | 44 capsule; magnifier x=12, text x=39 | measured | 3P-S1 |
| Alert | 320 wide, r34; 48 capsules inset 16, gap 8; 24 side padding; 17/13 type | measured (26.5) | 3P-S1 |
| Action sheet | 320 × r34 card; 48 capsules gap 8 | measured | 3P-S1 |
| Switch | 63×28 r14; knob 37×24 inset 2; travel 22 | measured (26.5) | 3P-S1 |
| Slider | track 6 r3; thumb 37×24; height 34 | measured | 3P-S1 |
| Segmented | 32 capsule; selection inset 2 (28 tall); 13 pt labels | measured | 3P-S1 |
| Stepper | 94×32 capsule | measured | 3P-S1 |
| Buttons | mini/small 28, medium 34, large 50; icon glass circle 34 | measured | 3P-S1 |
| Inset grouped list | inset 20 (16 on ≤375 wide); r26; rows 52 (73 with subtitle) | measured | 3P-S1 |
| Sheet corners | = display corner radius | measured, corroborated | 3P-S9, S13, S14, S15 |
| Floating sheet inset | ≈ 8 (Maps), shrinking to 0 at full height | observed | 3P-S14, S13 |
| Floating → regular sheet | ≈ 0.9 of screen height | observed, corroborated | 3P-S16, S17 |
| Grabber | 36×5 | measured | 3P-S1 |
| Page control | 7 dots, 17.7 pitch | measured | 3P-S1 |
| Text field roundedRect | 34 tall, r5 | measured | 3P-S1 |
| Display corner radii | 39.0 (X/Xs/11 Pro), 41.5 (Xr/11), 44.0 (12/13 mini), 47.33 (12/12 Pro/13/13 Pro/14/16e), 53.33 (12/13 Pro Max, 14 Plus), 55.0 (14 Pro–16), 62.0 (16 Pro/Pro Max, 17, 17 Pro/Pro Max, Air) | measured (private `_displayCornerRadius`) | 3P-S15 |
| Nav scroll edge extent (874-pt screen, from top) | hard band ends at 106 (inline title); soft fades to ~121–122 | measured (26.4) | 3P-S2 |
| Materialize / dematerialize | ~250 ms in / ~350 ms out (content blurs first, glass dissolves after) | measured (120 fps capture) | 3P-S42 |
| Press lift | ~+15 luma light mode; 150 ms in, 60 ms out | measured (light only) | 3P-S42 |
| Zoom-sheet swipe dismiss | 0.64 scale per card height; 1:1 to 0.48, rubber-band to 0.33 floor | measured | 3P-S42 |

### 9.3 Values nobody publishes (must be measured on device before claiming parity)

1. Regular/clear blur radius, luminosity/saturation curve, tint opacity per size.
2. Edge refraction profile and strength per size; chromatic aberration amount.
3. Specular rim width, intensity, light direction; whether in-app controls track device motion (only Home/Lock Screen confirmed [3P-S19, S51]).
4. Shadow radius/opacity and its adaptation curve over text vs light fills.
5. Light↔dark flip luminance threshold, hysteresis, timing; dependence on scroll speed [3P-S20].
6. Default `GlassEffectContainer` spacing; fixed `ToolbarSpacer` width; gap between separate toolbar capsules.
7. Interactive press scale, glow radius/spread to neighbours, bounce spring (response/damping).
8. Morph springs (button→menu, button→popover, search circle→field, tab lens, badge merge).
9. Minimized tab bar circle diameter and the minimize/expand animation.
10. Medium-detent sheet inset (≈8 vs full width conflict), corner radius per detent, opacity ramp.
11. Modal scrim opacity for sheets/alerts (0.4 and 54% both unverified).
12. Menu, popover and context-menu geometry (width, radius, item height) and preview lift scale.
13. Scroll edge band height/blur ramp for soft vs hard, and the iOS 27 "uniform toolbar" look.
14. Knob/thumb size while dragged (1.57× vs 1.25× disagreement).
15. Keyboard top-corner radius.
16. iOS 27 darkened-edge width/opacity and brighter-specular intensity.

---

## 10. Behaviors most implementations miss

Each line is a behaviour that separates "blurred rounded rectangle" from native Liquid Glass.

1. **It lenses, it doesn't just blur.** Light is bent and concentrated at the rim ("responsive lensing along its edges"); the centre stays comparatively clear. A plain Gaussian `BackdropFilter` is the old scattered-light material [W219, W102].
2. **Glass samples a region larger than itself**, so edge refraction pulls in content from just outside the shape [W323, W310].
3. **Glass never samples other glass.** Neighbouring glass must share one container/sampling pass or rendering becomes inconsistent; nested glass gives "double translucency" [W323, MWA208].
4. **No glass on glass.** Anything on top of glass is fills, transparency and vibrancy, never a second glass layer [W219].
5. **Small elements flip light↔dark with the backdrop, independent of system appearance; large ones (menus, sidebars) never flip**, and the glyphs on small glass flip in lockstep [W219, HIG-Color].
6. **One adaptation decision per container** — grouped buttons flip together, not one by one [W284, W310].
7. **Size changes the material.** Bigger = more opaque, thicker, deeper shadow, stronger lensing, softer scatter; smaller = clearer. A button growing into a menu *thickens during the morph* [W284, W219].
8. **Shadows adapt**: stronger over text, weaker over plain light backgrounds [W219].
9. **Tint is mapped to backdrop brightness**, not painted: a range of tones shifting hue/brightness/saturation with what is behind; a solid fill is wrong [W219, W284].
10. **Clear glass needs a separate dimming layer** (35% dark over bright content; Apple's example 30% black), optionally localised under small controls; never mix clear and regular [HIG-Materials, SUI, W219].
11. **Appear/disappear materializes** (lensing and blur ramp; content fades, glass does not alpha-fade); UIKit explicitly says never animate alpha. Measured ~250 ms in / ~350 ms out [W219, W284, 3P-S42].
12. **Droplet merging.** Shapes within the container spacing blend like liquid (smooth union), split by spawning at one point and animating apart, and are re-absorbed on collapse [W284, W323].
13. **Press response is scale *up* + bounce + shimmer + a glow starting under the finger that spreads to neighbouring glass**, with gel-like stretch following a drag; trackpad input is subdued [W219, W323, HIG-Motion].
14. **Controls lift into glass only while touched.** Switch knob, slider thumb and segmented selection are solid at rest and become a see-through lens while pressed; slider thumbs keep momentum and stretch [W219, W284].
15. **Tab bar selection lens.** Dragging across tabs lifts the selection into a refracting droplet with chromatic aberration that deforms icons beneath; no public API [3P-S19, community lab transcript].
16. **Search tab is a separate circle that morphs into the field**, and the field replaces the tab bar; in iOS 27 it may be a "prominent" button tab that jumps straight to the keyboard [W256, W323, HIG-SearchFields].
17. **Tab bar minimizes on the *start* of a user drag** (not programmatic scroll), collapses to the current tab as a circle, and the accessory drops inline between it and the search circle; restores on reverse scroll, tapping a tab, or reaching the top [SUI, 3P-S3, S19, HIG-TabBars].
18. **Toolbar grouping rules.** Icon buttons share one capsule; text buttons, Done/Close and prominent buttons get their own; never mix text and a symbol in one capsule; a zero-width fixed space splits capsules; a flexible space separates backgrounds unless told not to [W284, HIG-Toolbars, ADOPT].
19. **Bars are transparent; content scrolls under everything**, including the large title which now lives in the scroll content and scrolls under the bar [W284, HIG-Layout].
20. **Scroll edge effect replaces bar backgrounds**: soft progressive blur+fade on iOS 26, switching to a subtle dim over dark content; hard only for dense UIs/pinned headers; one per view, never mixed; its shape follows the floating controls; iOS 27 replaces the automatic look with a uniform top toolbar [W219, W356, W310, W26-102, W26-278].
21. **Presentations emanate from their source.** Menus pop open out of their button; popovers animate from and *replace* the bar button until dismissed; sheets can zoom out of a toolbar button; action sheets appear over the tapped control with no Cancel; dialogs morph out of their button; all collapse back on dismiss [W219, W284, W323, W356, UIK sourceItem].
22. **Sheets change material with height.** Partial detents float inset with bottom corners nesting in the display curve and interactive glass (finger-tracking flare); dragging up the inset shrinks, the corners follow, and near full height (~0.9) the sheet becomes opaque and edge-anchored [W323, W356, 3P-S13, S14, S16].
23. **Concentric corners everywhere.** Inner radius = outer radius − inset; sheets and popovers are containers; bars' items are concentric with the bar; near the screen edge use a capsule with extra margin [W356, SUI, HIG-Toolbars].
24. **Toolbar items morph across push/pop** instead of cross-fading; navigation transitions are interruptible [W256, W243, UIK identifier].
25. **Monochrome by default.** Toolbar and tab icons are monochrome and vibrant; colour goes into content, and only the single primary action is tinted [W323, W356, HIG-Color, W26-251].
26. **Ambient spill.** Large glass picks up light from nearby colourful content and it bleeds into the shadow [W219].
27. **Specular rim travels around the silhouette** on interactions (e.g. unlock) and, on icons/Lock Screen, with device tilt; sharp corners break it [W219, W220]. iOS 27 adds a darkened edge and brighter specular [W26-102].
28. **Accessibility variants are material changes, not opacity tweaks**: Reduce Transparency = frostier; Increase Contrast = black/white with a contrasting border; Reduce Motion = no elasticity, reduced effects; Show Borders; Tinted/slider; Reduce Bright Effects [W219, 3P-S25, S29].
29. **Menus no longer blur the content behind them** (Messages long-press no longer dims the thread) [3P-S19, S52].
30. **Floating glass sidebar and background extension**: hero images are mirrored and blurred under the sidebar/inspector rather than cropped [W323, SUI].
31. **Glass hit-testing vs highlight**: the pill highlights anywhere on touch-down but the hit region may be just the glyph (device-only) [3P-S4].
32. **Buttons use `labelColor`, tint on a plain bar item colours only the glyph; `.prominent` tints the background** [W284].

---

## 11. Official sample code and resources

| Resource | URL | What it demonstrates | Size |
|---|---|---|---|
| Landmarks: Building an app with Liquid Glass (sample code) | https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass | NavigationSplitView app for iPhone/iPad/Mac; `backgroundExtensionEffect` hero images; horizontal scroll under sidebar/inspector; toolbar grouping with `ToolbarSpacer(.fixed/.flexible)` + `ToolbarItemGroup`; custom badges with `GlassEffectContainer` + `glassEffect(.regular, in: .rect(cornerRadius:))` + `glassEffectID` morph toggled by a `.glass` button; 4-layer Icon Composer icon (light/dark/clear/tinted). Requires iOS/iPadOS/Mac Catalyst/macOS 26.0, Xcode 26.0. File `LandmarksBuildingAnAppWithLiquidGlass.zip` (path segment `a88428e6793e/`) | **Not shown** (doc JSON has no size; `checksum: null`). Not downloaded. |
| Landmarks sub-article: Applying a background extension effect | https://developer.apple.com/documentation/swiftui/landmarks-applying-a-background-extension-effect | `Image(decorative:)` → `.backgroundExtensionEffect()` → `.overlay(alignment: .bottom)` | — |
| Landmarks sub-article: Extending horizontal scrolling under a sidebar or inspector | https://developer.apple.com/documentation/swiftui/landmarks-extending-horizontal-scrolling-under-a-sidebar-or-inspector | `ScrollView(.horizontal)` + `LazyHStack` scrolling under the sidebar | — |
| Landmarks sub-article: Refining the system provided Liquid Glass effect in toolbars | https://developer.apple.com/documentation/swiftui/landmarks-refining-the-system-provided-glass-effect-in-toolbars | Share / fixed / [Favorite+Collections] / fixed / Info grouping | — |
| Landmarks sub-article: Displaying custom activity badges | https://developer.apple.com/documentation/swiftui/landmarks-displaying-custom-activity-badges | `GlassEffectContainer(spacing: Constants.badgeGlassSpacing)`, `glassEffectID`, `withAnimation` toggle; constant values only inside the zip | — |
| Article: Applying Liquid Glass to custom views | https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views | glassEffect, tint, interactive, containers, union, morph, performance | — |
| Article: Adopting Liquid Glass | https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass | System-wide adoption checklist incl. sheets, lists, search, action sheets, backward compatibility | — |
| Technology overview: Liquid Glass | https://developer.apple.com/documentation/technologyoverviews/liquid-glass | Hub linking the above and WWDC25 219/356/323/284/310 | — |
| Apple Design Resources | https://developer.apple.com/design/resources/ | Now lists iOS/iPadOS 27 Figma and Sketch kits (27 kit posted 2026-09-17); iOS 26 kit no longer listed there (community file id 1527721578857867021) [HIG What's new, 3P-S55] | — |
| New design gallery (2026) | https://developer.apple.com/design/new-design-gallery-2026 | Showcase of apps using the design [3P] | — |

No other official Liquid Glass sample-code project was found (searches of developer.apple.com for UIKit/AppKit Liquid Glass samples returned only Landmarks) [3P, SUI agent].

---

## 12. Source index

### 12.1 Apple

**HIG** (human URL `https://developer.apple.com/design/human-interface-guidelines/<slug>`; JSON
`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`):
materials, color, tab-bars, toolbars (navigation-bars now merged here; its JSON 404s), sidebars,
scroll-views, layout, buttons, search-fields, sheets, popovers, menus, pull-down-buttons, pop-up-buttons,
context-menus, edit-menus, alerts, action-sheets, segmented-controls, sliders, toggles, steppers,
pickers, lists-and-tables, page-controls, text-fields, labels, progress-indicators, split-views,
tab-views, windows, motion, accessibility, dark-mode, typography, app-icons, widgets.
HIG What's new: https://developer.apple.com/design/whats-new/ (Liquid Glass change-log dates:
2025-06-09, 2025-07-28, 2025-09-09, 2025-12-16, 2026-03-24, 2026-06-08, 2026-09-09, 2026-09-17).

**SwiftUI reference** (https://developer.apple.com/documentation/swiftui/...): glass, glass/regular,
glass/clear, glass/identity, glass/tint(_:), glass/interactive(_:), view/glasseffect(_:in:),
defaultglasseffectshape, glasseffectcontainer, glasseffectcontainer/init(spacing:content:),
view/glasseffectid(_:in:), view/glasseffectunion(id:namespace:), view/glasseffecttransition(_:),
glasseffecttransition (matchedgeometry, materialize, identity), primitivebuttonstyle/glass,
primitivebuttonstyle/glass(_:), primitivebuttonstyle/glassprominent, glassbuttonstyle,
glassprominentbuttonstyle, view/buttonbordershape(_:), buttonbordershape, controlsize/extralarge,
toolbarspacer, spacersizing, toolbarcontent/sharedbackgroundvisibility(_:), toolbaritemplacement,
view/navigationsubtitle(_:), defaulttoolbaritem, toolbardefaultitemkind, view/tabbarminimizebehavior(_:),
tabbarminimizebehavior, view/tabviewbottomaccessory(content:), view/tabviewbottomaccessory(isenabled:content:),
tabviewbottomaccessoryplacement, environmentvalues/tabviewbottomaccessoryplacement, tab, tabrole/search,
tabrole/prominent, view/tabviewsearchactivation(_:), tabsearchactivation, view/searchtoolbarbehavior(_:),
searchtoolbarbehavior, view/searchable(text:placement:prompt:), searchfieldplacement,
view/scrolledgeeffectstyle(_:for:), scrolledgeeffectstyle, view/scrolledgeeffecthidden(_:for:),
view/backgroundextensioneffect(), concentricrectangle, edge/corner/style, shape/rect(corners:isuniform:),
roundedrectangularshape, view/containershape(_:), containerrelativeshape, view/presentationdetents(_:),
view/presentationbackground(_:), view/presentationbackgroundinteraction(_:), view/presentationcornerradius(_:),
view/navigationtransition(_:), navigationtransition/zoom(sourceid:in:), view/matchedtransitionsource(id:in:),
toolbarcontent/matchedtransitionsource(id:in:), slider, view/sliderthumbvisibility(_:), toggle, menu,
view/glassbackgroundeffect(displaymode:) (visionOS only), toolbaroverflowmenu, toolbarcontent/visibilitypriority(_:),
view/toolbarminimizationbehavior(_:for:), toolbarcontent/contentmarginsremoved(_:), navigationtransition/crossfade.

**UIKit reference** (https://developer.apple.com/documentation/uikit/...): uiglasseffect (init(style:),
style, isinteractive, tintcolor), uiglasscontainereffect (spacing), uivisualeffectview,
uibutton/configuration-swift.struct/glass() | prominentglass() | clearglass() | prominentclearglass(),
uibutton/configuration-swift.struct/size, cornerstyle-swift.enum, uiscrolledgeeffect, uiscrolledgeeffect/style-swift.class,
uiscrollview/topedgeeffect (bottom/left/right), uiscrolledgeelementcontainerinteraction,
uicornerconfiguration-swift.struct, uicornerradius-swift.struct, uiview/cornerconfiguration-7l0ja,
uiview/effectiveradius(corner:), uibackgroundextensionview, uibarbuttonitem/hidessharedbackground,
uibarbuttonitem/sharesbackground, uibarbuttonitem/style-swift.enum, uibarbuttonitem/fixedspace(),
uibarbuttonitemgroup/fixedspace(), uibarbuttonitem/badge-4sz3f, uibarbuttonitem/identifier,
uibarbuttonitem/ispaddingremoved, uinavigationitem (subtitle, largetitle, largesubtitleview,
searchbarplacement-swift.enum, searchbarplacementbarbuttonitem), uibarminimization-swift.struct,
uitabbarcontroller/tabbarminimizebehavior, uitabbarcontroller/minimizebehavior, uitabaccessory,
uitabaccessory/environment, uisearchtab, uislider/sliderstyle, uislider/trackconfiguration-6m55i,
uisheetpresentationcontroller (+ detent/backgroundeffect), uipopoverpresentationcontroller/sourceitem,
uiviewcontroller/transition (zoom(options:sourcebarbuttonitemprovider:)), uiview/layoutregion,
uiview/animationoptions/flushupdates. Info.plist key:
https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility

**Articles and samples:** see §11.

**WWDC25 sessions** (https://developer.apple.com/videos/play/wwdc2025/<id>/): 219 Meet Liquid Glass;
356 Get to know the new design system; 323 Build a SwiftUI app with the new design; 284 Build a UIKit app
with the new design; 310 Build an AppKit app with the new design; 256 What's new in SwiftUI; 243 What's
new in UIKit; 208 Elevate the design of your iPad app; 220 Say hello to the new look of app icons; 361
Create icons with Icon Composer; 278 What's new in widgets; 334 What's new in watchOS 26; 337 What's new
in SF Symbols 7; 102 Platforms State of the Union; 281, 282 (minor). Meet with Apple:
https://developer.apple.com/videos/play/meet-with-apple/208/ and /201/.

**WWDC26 sessions** (https://developer.apple.com/videos/play/wwdc2026/<id>/): 102 Platforms State of
the Union; 269 What's new in SwiftUI; 278 Modernize your UIKit app; 289 Modernize your AppKit app; 292
Design intuitive search experiences; 251 Communicate your brand identity on iOS; 8120 SwiftUI Group Lab.

**Other Apple:** Newsroom 2025-06-09
https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/ ;
iPhone User Guide "Adjust iPhone display and text settings"
https://support.apple.com/guide/iphone/adjust-iphone-display-and-text-settings-iphd6804774e/ios (Liquid
Glass Clear/Tinted, via search snippet; the page body did not render for the fetcher).

### 12.2 Additional third-party sources used directly in this file

- 3P-Engadget: https://www.engadget.com/mobile/smartphones/how-to-adjust-the-liquid-glass-effect-in-ios-261-203634681.html
- 3P-OSXDaily (Show Borders, 2026-01-21): https://osxdaily.com/2026/01/21/use-show-borders-to-clarify-liquid-glass-ui-on-ipados-26-ios-26/
- 3P-iDownloadBlog (Show Borders, 2026-09-24): https://www.idownloadblog.com/2026/09/24/show-borders-ios-macos/
- 3P-NilCoalescing Button Shapes (2022): https://nilcoalescing.com/blog/ButtonShapesSetting/
- 3P-MacRumors iOS 27 changes (2026-06-10): https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/
- 3P-CultOfMac iOS 27 changes: https://www.cultofmac.com/news/liquid-glass-changes-ios-27-macos-27
- 3P-Unagar prominent tab: https://www.sagarunagar.com/blog/swiftui-prominent-tab-is-not-a-floating-action-button/
- 3P-Crosley iOS 27 SwiftUI: https://blakecrosley.com/blog/whats-new-swiftui-ios-27
- WWDC25 SwiftUI group lab community transcript: https://gist.github.com/samhenrigold/1e05a0dfa83ca953e7b99219e6bd9615

### 12.3 Third-party measurement and behaviour sources (3P-S<n>)


- 3P-S1. applecn (STiXzoOR), "Apple design system reference" §11 and `packages/ui/src/tokens/{metrics,radii,materials,motion,elevation}.ts`. https://github.com/STiXzoOR/applecn, site https://applecn.vercel.app/. iOS values dumped from UIKit view trees, iPhone 17 Pro simulator, **iOS 26.5**, 2026-09-06. Continuous corners fitted from screenshots. Materials, motion and elevation come from **Apple's web CSS** (2026-09-05). Repo has 0 stars and appears AI-assisted.
- 3P-S2. Maui.Spine (jonatansoderberg): PR #378 "iOS 26 header bar is 10 pt shorter than UINavigationBar" (2026-09-24), issues #366, #385. https://github.com/jonatansoderberg/Maui.Spine/pull/378. Measured against native UINavigationController, iPhone 17 sim **26.4**, and on **26.5** for #385.
- 3P-S3. core-platform-ios (arnaudmaillet) PR #154 (2026-09-10), "What UIKit actually does, measured". https://github.com/arnaudmaillet/core-platform-ios/pull/154. UITests with real-finger drags.
- 3P-S4. NativePHP/mobile-air issue #442 / PR #443 (2026-09-13). https://github.com/NativePHP/mobile-air/issues/442. Physical iOS 26 device.
- 3P-S5. olamva/f1 PR #116 (2026-09-26). https://github.com/olamva/f1/pull/116. "measurements of native iOS 26 apps", method not detailed.
- 3P-S6. JesusFilm/forge PR #2284 (2026-09-14). https://github.com/JesusFilm/forge/pull/2284. Safe-area inset spike on 18.6 and **26.5**.
- 3P-S7. Apple Developer Forums 796986, "UITabBar in iOS 26 is Too Big for Touch ID Devices" (FB19648533). https://developer.apple.com/forums/thread/796986.
- 3P-S8. Erik D. Kennedy, "iOS 26 Design Guidelines: Illustrated Patterns", learnui.design, updated 2026-04-22. https://www.learnui.design/blog/ios-design-guidelines-templates.html.
- 3P-S9. Natalia Panferova, "Presenting Liquid Glass sheets in SwiftUI on iOS 26", Nil Coalescing, 2025-07-18. https://nilcoalescing.com/blog/PresentingLiquidGlassSheetsInSwiftUI/.
- 3P-S10. Natalia Panferova, "SwiftUI Liquid Glass sheets with NavigationStack and Form", 2025-09-09. https://nilcoalescing.com/blog/LiquidGlassSheetsWithNavigationStackAndForm/.
- 3P-S11. Natalia Panferova, "SwiftUI Search Enhancements in iOS and iPadOS 26", 2025-07-28. https://nilcoalescing.com/blog/SwiftUISearchEnhancementsIniOSAndiPadOS26/.
- 3P-S12. Natalia Panferova, "Corner concentricity in SwiftUI on iOS 26", 2025-08-21. https://nilcoalescing.com/blog/ConcentricRectangleInSwiftUI/.
- 3P-S13. Arunabh Verma, "How to create Apple Maps style liquid glass sheets in Expo (the real way)", Expo blog, 2025-11-25. https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets.
- 3P-S14. S1xinch/View-Finder issue #62 / PR #63 (2026-09-23). https://github.com/S1xinch/View-Finder/issues/62.
- 3P-S15. kylebshr/ScreenCorners README (display corner radii). https://github.com/kylebshr/ScreenCorners.
- 3P-S16. software-mansion/react-native-screens issue #4605 (2026-09-06). https://github.com/software-mansion/react-native-screens/issues/4605. **26.5** sim and device.
- 3P-S17. lodev09/react-native-true-sheet issue #652 (2026-04-16) and PR #845 (2026-09-16). https://github.com/lodev09/react-native-true-sheet/issues/652.
- 3P-S18. software-mansion/react-native-screens issue #4728 (2026-09-25). https://github.com/software-mansion/react-native-screens/issues/4728. iPhone Duo sim, **iOS 27.1**.
- 3P-S19. Federico Viticci, "iOS and iPadOS 26: The MacStories Review", pages 2–4, Sept 2025. https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/2/ (and /3/, /4/).
- 3P-S20. Dan Moren, "iOS 26 Review: Through a glass, liquidly", Six Colors, 2025-09-15. https://sixcolors.com/post/2025/09/ios-26-review-through-a-glass-liquidly/.
- 3P-S21. Raluca Budiu, "Liquid Glass Is Cracked, and Usability Suffers in iOS 26", NN/g, 2025-10-10. https://www.nngroup.com/articles/liquid-glass/. No measurements.
- 3P-S22. Juli Clover, "iOS 26 Liquid Glass Design Drama: Beta 2 vs. Beta 3 Changes in Every App", MacRumors, 2025-07-08. https://www.macrumors.com/guide/ios-26-beta-3-liquid-glass-changes/.
- 3P-S23. Ryan Christoffel, "iOS 26 beta 4 adds more 'liquid' back to Liquid Glass design", 9to5Mac, 2025-07-22. https://9to5mac.com/2025/07/22/ios-26-beta-4-adds-more-liquid-back-to-liquid-glass-design/.
- 3P-S24. GSMArena, "iOS 26 Beta 2 tones down the Liquid Glass effect" (search summary only). https://www.gsmarena.com/ios_26_beta_2_tones_down_the_liquid_glass_effect-news-68379.php.
- 3P-S25. Tim Hardwick, "iOS 26.1: Reduce Liquid Glass Effects With Apple's New Toggle", MacRumors, 2025-11-04. https://www.macrumors.com/how-to/ios-26-1-reduce-liquid-glass-effects/.
- 3P-S26. Sarah Perez, "With iOS 26.2, Apple lets you roll back Liquid Glass again — this time on the Lock Screen", TechCrunch, 2025-12-12. https://techcrunch.com/2025/12/12/with-ios-26-2-apple-lets-you-roll-back-liquid-glass-again-this-time-on-the-lock-screen/.
- 3P-S27. MacRumors, "iOS 26.2 Lock Screen Gets Liquid Glass Slider", 2025-11-04 (search summary). https://www.macrumors.com/2025/11/04/ios-26-2-liquid-glass-slider/.
- 3P-S28. Gavin Anderegg, "Liquid Glass updates in 26.4", 2026-03-29. https://anderegg.ca/2026/03/29/liquid-glass-updates-in-264.
- 3P-S29. Ryan Christoffel, "iOS 26.4 adds setting to let you change new Liquid Glass effect", 9to5Mac, 2026-04-10. https://9to5mac.com/2026/04/10/ios-26-4-adds-setting-to-let-you-change-new-liquid-glass-effect/.
- 3P-S30. Ben Dodson, "Restoring the traditional icon-based tab bar on iPad with Liquid Glass", 2026-01-22. https://bendodson.com/weblog/2026/01/22/traditional-tab-bar-on-ipados-26/.
- 3P-S31. Majid Jabrayilov, Swift with Majid "Glassifying" series: tabs (2025-06-24), toolbars (2025-07-01), custom views (2025-07-16), groups (2025-07-23). https://swiftwithmajid.com/2025/06/24/glassifying-tabs-in-swiftui/ (and the /07/01, /07/16, /07/23 posts).
- 3P-S32. Donny Wals, "Exploring tab bars on iOS 26 with Liquid Glass" (2025-06-19, upd. 07-07) and "Designing custom UI with Liquid Glass on iOS 26" (2025-07-01, upd. 07-10). https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/, https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/.
- 3P-S33. Antonella Giugliano, Create with Swift: "Making the tab bar collapse while scrolling" (2025-08-28), "Enhancing the tab bar with a bottom accessory" (2025-09-02). https://www.createwithswift.com/making-the-tab-bar-collapse-while-scrolling/, https://www.createwithswift.com/enhancing-the-tab-bar-with-a-bottom-accessory/.
- 3P-S34. Seb Vidal, "What's New in UIKit 26", 2025-08-13. https://sebvidal.com/blog/whats-new-in-uikit-26/.
- 3P-S35. JuniperPhoton, "Adopting Liquid Glass: Experiences and Pitfalls", 2025-10-03. https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences.
- 3P-S36. Fatbobman (Grow team, Shuhari), "Grow on iOS 26 - Liquid Glass Adaptation in UIKit + SwiftUI Hybrid Architecture", 2025-11-12. https://fatbobman.com/en/posts/grow-on-ios26/.
- 3P-S37. Ralf Ebert, SwiftUI Garden, "Standalone Glass Buttons widen to a capsule when tapped". https://swiftui-garden.com/Misc/iOS-26/Standalone-Glass-Buttons-widen-to-a-capsule-when-tapped.
- 3P-S38. Paul Hudson, "How to adjust the scroll edge effect for ScrollView and List", Hacking with Swift, 2025-06-19. https://www.hackingwithswift.com/quick-start/swiftui/how-to-adjust-the-scroll-edge-effect-for-scrollview-and-list.
- 3P-S39. kube.io, "Liquid Glass in the Browser: Refraction with CSS and SVG", 2025-09-04. https://kube.io/blog/liquid-glass-css-svg/.
- 3P-S40. whynotmake-it, `liquid_glass_renderer` (Flutter), repo flutter_liquid_glass (444★, active 2026-09). https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer. Read: README, `liquid_glass_settings.dart`, `stretch.dart`, `render.glsl`.
- 3P-S41. DnV1eX, LiquidGlassKit (445★, 2025-12 to 2026-01). https://github.com/DnV1eX/LiquidGlassKit. Read: README, `LiquidGlassSlider.swift`, `LiquidGlassSwitch.swift`, `LiquidLensView.swift`, `LiquidGlassView.swift`.
- 3P-S42. sdegenaar, `liquid_glass_widgets` (Flutter, 676★, active 2026-09-25). https://github.com/sdegenaar/liquid_glass_widgets. Read: `glass_defaults.dart`, `glass_sheet_defaults.dart`, `tab_bar_bottom_layout.dart`, `glass_tab_bar.dart`, `glass_slider.dart`, `glass_switch.dart`, `glass_menu.dart`, `glass_dialog.dart`, `docs/GLASS_MODAL_SHEETS_GUIDE.md`, `docs/LIQUID_MORPH_ENGINE.md`, `docs/POPOVER_BLUR_RAMP.md`.
- 3P-S43. Conor Luddy, LiquidGlassReference README (screenshot dated 2025-11-16). https://github.com/conorluddy/LiquidGlassReference (also https://www.conor.fyi/writing/liquid-glass-reference). Mostly API. Its "13% battery drain vs 1% in iOS 18 (iPhone 16 Pro Max testing)" line has no source (CLAIMED).
- 3P-S44. Apple, "Landmarks: Building an app with Liquid Glass" (sample). https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass.
- 3P-S45. Apple HIG, Materials (35 % dimming layer for clear glass). https://developer.apple.com/design/human-interface-guidelines/materials.
- 3P-S46. Apple WWDC25 session 219 "Meet Liquid Glass" transcript. https://developer.apple.com/videos/play/wwdc2025/219/.
- 3P-S47. WWDCNotes, "Meet Liquid Glass". https://wwdcnotes.com/documentation/wwdc25-219-meet-liquid-glass/.
- 3P-S48. Roger Wong, "Breaking Down Apple's Liquid Glass", 2025-06-11. https://rogerwong.me/2025/06/breaking-down-apples-liquid-glass.
- 3P-S49. Josh Cusick, "Apple's Liquid Glass seemed like a disaster...until I looked closer", 2025-11-19. https://joshcusick.substack.com/p/apples-liquid-glass-seemed-like-a-disaster-until-i-looked-closer.
- 3P-S50. Geoff Graham, "Getting Clarity on Apple's Liquid Glass", CSS-Tricks, 2025-07-17. https://css-tricks.com/getting-clarity-on-apples-liquid-glass/.
- 3P-S51. Raymond Wong, "This Liquid Glass Optical Illusion on iOS 26 Is Driving Me Insane", Gizmodo, 2025-09-16. https://gizmodo.com/this-liquid-glass-optical-illusion-on-ios-26-is-driving-me-insane-2000659413.
- 3P-S52. Radu Tyrsina, "iOS 26 Removes Blurry Background in Messages", MacObserver, 2025-10-02. https://www.macobserver.com/news/ios-26-removes-blurry-background-in-messages-here-are-the-best-alternatives/.
- 3P-S53. Ryan Ashcraft, "My Beef with the iOS 26 Tab Bar" (2026-01-05) and "Introducing FabBar" (2026-01-26), ryanwesley.com; Neil Macy, "Liquid Glass Tab Bar Actions Aren't Fab". https://ryanwesley.com/ios-26-tab-bar-beef/, https://ryanwesley.com/introducing-fabbar/, https://www.neilmacy.co.uk/blog/liquid-glass-fab-bar-actions-not-fab/.
- 3P-S54. Figma Learn, "Apply effects to layers" (Glass effect). https://help.figma.com/hc/en-us/articles/360041488473-Apply-effects-to-layers.
- 3P-S55. Apple Design Resources. https://developer.apple.com/design/resources/ (now iOS 27 kits).
- 3P-S56. rdev/liquid-glass-react README (6.3k★). https://github.com/rdev/liquid-glass-react.
- 3P-S57. water-rs/waterui PR #801 (minimize) and #802 (bottom accessory), 2026-09-14. https://github.com/water-rs/waterui/pull/801.
- 3P-S58. Tim Hardwick, "iOS 26: Reduce Transparency of Apple's Liquid Glass Design", MacRumors, 2025-09-03. https://www.macrumors.com/how-to/ios-reduce-transparency-liquid-glass-effect/.
- 3P-S59. Espen Benoni, "UI Changes in iOS 26 That's Not About Liquid Glass", Design for Native, 2025-08-23. https://designfornative.com/ui-changes-in-ios-26-thats-not-about-liquid-glass/.
- 3P-S60. Mick MacCallum, "Building Interactive Glass Controls in SwiftUI", bleepingswift, 2025-12-21. https://bleepingswift.com/blog/interactive-glass-effects-swiftui. Numbers are the author's own design choices.
- 3P-S61. Livsy Code, "ConcentricRectangle and Corner Radius Consistency", 2025-08-05. https://livsycode.com/swiftui/concentricrectangle-and-corner-radius-consistency/.

- 3P-S62. MetaMask mobile: PR #36658 "fix(navbar): match the floating tab bar to the native iOS 26 bar" (2026-09-22) and `TabBarFloating.constants.ts`. https://github.com/MetaMask/metamask-mobile/pull/36658. Measured from screenshots calibrated on the 62-pt pill.
- 3P-S63. wix/react-native-navigation, `.cursor/skills/ios26-navigation/SKILL.md` (2026-05-14). https://github.com/wix/react-native-navigation/blob/master/.cursor/skills/ios26-navigation/SKILL.md. Maintainers' API and behaviour notes, no measurements.
- 3P-S65. Darryl Bayliss, "An Introduction to Liquid Glass for iOS 26", Kodeco, 2026-02-04. https://www.kodeco.com/49905345-an-introduction-to-liquid-glass-for-ios-26.
- 3P-S66. Apple Developer Forums 801060, "Inaccessible background of the system keyboard in iOS 26 (liquid glass)", Sept 2025. https://developer.apple.com/forums/thread/801060.
- 3P-S64. flutter/flutter#170310 "Support for iOS 26 'Liquid Glass' Design in Cupertino Widgets". https://github.com/flutter/flutter/issues/170310. Search summary only.

Not reachable during this pass: sarunw.com (fetch failed twice; only a search snippet was used), obra.studio (DNS
failure), the Figma Community "Control Center UI Kit" page (403). Raw copies of the GitHub READMEs and source files
read are in `glass-research/raw/`.

### 12.4 Working notes behind this file

Full per-source notes (quotes, declarations, code snippets) live beside this file:
`notes-hig.md`, `notes-swiftui.md`, `notes-uikit.md`, `notes-wwdc.md`, `notes-thirdparty.md`, and
GitHub READMEs/sources read by the third-party pass in `raw/`.
