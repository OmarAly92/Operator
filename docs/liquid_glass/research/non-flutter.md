# Non-Flutter Liquid Glass implementations — research survey

Scope: rendering/motion techniques from non-Flutter codebases and write-ups that a Flutter
team could port to a fragment shader (`FragmentProgram`/`ImageFilter.shader`) composited over
a `BackdropFilterLayer` under Impeller. Research only, no repo files touched.

---

## 1. Android / Compose

### Kyant0/AndroidLiquidGlass ("backdrop") — https://github.com/Kyant0/AndroidLiquidGlass

**Approach.** Compose Multiplatform library (Maven `io.github.kyant0:backdrop`, Apache-2.0).
Architecture is the closest existing analogue to what a Flutter port would build:

- `LayerBackdrop` (`backdrop/src/commonMain/kotlin/com/kyant/backdrop/backdrops/LayerBackdrop.kt`)
  wraps a `GraphicsLayer` (Compose's real snapshot-able layer, the same concept as Flutter's
  `BackdropFilterLayer`/`Scene` layer tree) and redraws it with an inverse translate so the
  glass element samples the *actual* content behind it, not a copy. `CombinedBackdrop.kt` lets
  several backdrops (e.g. blurred content + another glass layer) compose by drawing each in turn.
- The optical effect itself is a real GPU fragment shader: AGSL (Android's SkSL-like shading
  language) compiled through `android.graphics.RuntimeShader`, applied via `RenderEffect`
  (`backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects/Lens.kt` +
  `.../internal/Shaders.kt`, `kmp` branch). This is architecturally identical to what
  `ui.FragmentProgram` + `ImageFilter.shader` would do in Flutter.

**Concrete technique — refraction shader** (`RoundedRectRefractionShaderString`, AGSL):

```c
float sd = sdRoundedRect(centeredCoord, halfSize, radius);   // signed distance to rounded-rect
if (-sd >= refractionHeight) return content.eval(coord);      // outside the bevel band: passthrough
sd = min(sd, 0.0);
float d = circleMap(1.0 - -sd / refractionHeight) * refractionAmount;
// circleMap(x) = 1.0 - sqrt(1.0 - x*x)   — a quarter-circle profile, NOT smoothstep
float2 grad = normalize(gradSdRoundedRect(...) + depthEffect * normalize(centeredCoord));
float2 refractedCoord = coord + d * grad;
return content.eval(refractedCoord);
```

`refractionAmount` is passed in **negated** (`setFloatUniform("refractionAmount", -refractionAmount)`
in `Lens.kt`) — the bevel pulls samples inward (a real convex lens), not outward.

**Dispersion.** `RoundedRectRefractionWithDispersionShaderString` does a 7-tap spectral sweep
(red/orange/yellow/green/cyan/blue/purple), each tap displaced by a fraction of
`dispersedCoord = d * grad * dispersionIntensity`, weighted and summed — a cheap approximation
of prismatic spread rather than a true wavelength simulation.

**Highlight.** `DefaultHighlightShaderString`/`AmbientHighlightShaderString` project the same
`gradSdRoundedRect` normal onto a light-direction vector (`dot(grad, normal)`) and raise it to a
`falloff` power — i.e. a Blinn-Phong-style rim computed from the identical SDF gradient used for
refraction, so highlight and lensing stay geometrically consistent.

**Fidelity.** Highest of the non-Flutter ports I could inspect at the code level: real captured
backdrop (no rasterize-to-PNG step), a real compiled fragment shader (not a baked displacement
texture), and a quarter-circle bevel profile that independently matches what the CSS/SVG authors
(`ALEXalesha/LiquidGlass`, `kube.io`) converged on by trial and error. No public source calls it
"the most faithful Android port" verbatim, but its `docs.` note it targets exact parity with the
WWDC25 "Meet Liquid Glass" session, and the shader design matches every other high-fidelity
source in this survey (see §6 for the convergence).

Reference doc: https://kyant.gitbook.io/backdrop (not fetched in depth; README points there).

---

## 2. Web

### kube.io — "Liquid Glass in the Browser: Refraction with CSS and SVG" — https://kube.io/blog/liquid-glass-css-svg/

**Approach.** Article-plus-interactive-demo. Derives the effect from Snell's law
(`n1 sin θ1 = n2 sin θ2`, air n=1, glass n≈1.5, single refraction event, normal incidence) rather
than an ad hoc curve, then bakes the result into an SVG `feDisplacementMap`.

**Height/bevel functions** (four selectable profiles):

```
convex circle:   y = sqrt(1 - (1-x)^2)
convex squircle: y = (1 - (1-x)^4)^(1/4)
concave:         y = 1 - convex(x)
lip:             y = mix(convex(x), concave(x), smootherstep(x))
```

Surface normal from the numeric derivative (`(f(x+δ)-f(x-δ))/2δ`), then 127 simulated rays per
radius bucket produce a displacement magnitude table, converted to Cartesian `(cos θ, sin θ)·mag`,
normalized to 8-bit range and packed `r = 128 + x·127, g = 128 + y·127` into a canvas → `feImage`
→ `feDisplacementMap scale=maxDisplacement xChannelSelector="R" yChannelSelector="G"`. Applied as
`backdrop-filter: url(#filter)`. Chrome-only (SVG filter as `backdrop-filter` isn't implemented
elsewhere). No chromatic aberration; specular rim is manually tuned filter compositing, not a
formula.

**Fidelity.** Strong physical grounding for the *shape* of the bevel; weak on dispersion/rim
(admits it's hand-tuned). Good pedagogical source for the Snell's-law derivation.

### shuding/liquid-glass — https://github.com/shuding/liquid-glass

**Approach.** A ~250-line paste-into-console vanilla JS toy (not a maintained library). Core:

```js
function roundedRectSDF(x, y, width, height, radius) {
  const qx = Math.abs(x) - width + radius;
  const qy = Math.abs(y) - height + radius;
  return Math.min(Math.max(qx, qy), 0) + length(Math.max(qx,0), Math.max(qy,0)) - radius;
}
fragment: (uv) => {
  const distanceToEdge = roundedRectSDF(ix, iy, 0.3, 0.2, 0.6);
  const displacement = smoothStep(0.8, 0, distanceToEdge - 0.15);
  const scaled = smoothStep(0, 1, displacement);
  return texture(ix * scaled + 0.5, iy * scaled + 0.5);
}
```
It rasterizes this per-pixel CPU function into a `Uint8ClampedArray` displacement map every
frame (`updateShader()`), normalizes by the observed max displacement, and drives an
`feDisplacementMap`. `backdrop-filter: url(#filter) blur(0.25px) contrast(1.2) brightness(1.05)
saturate(1.1)`.

**Fidelity.** Low — uses `smoothStep` (a soft symmetric bump) rather than the quarter-circle
profile, which is exactly the "looks like a highlight, not glass" failure mode later sources
(kube.io, ALEXalesha) explicitly call out. Useful mainly as the historically first, most-copied
reference (its README explicitly says other projects, e.g. `nikdelvin/liquid-glass`, are
adaptations) and for the minimal `feDisplacementMap` wiring pattern.

### rdev/liquid-glass-react — https://github.com/rdev/liquid-glass-react

**Approach.** React component wrapping the SVG-filter technique, with real chromatic aberration:
three separate `feDisplacementMap` passes (R/G/B), each with its own `scale`, recombined with
`feBlend mode="screen"`, masked to the rim by a radial-gradient-based edge mask
(`feColorMatrix` → `feComponentTransfer` discrete table) so the un-refracted center stays sharp
while aberration only appears at the edge:

```jsx
<feDisplacementMap in="SourceGraphic" in2="DISPLACEMENT_MAP"
  scale={displacementScale * (mode==="shader"?1:-1)} xChannelSelector="R" yChannelSelector="B" result="RED_DISPLACED" />
... // GREEN_DISPLACED with scale offset by -aberrationIntensity*0.05
... // BLUE_DISPLACED with scale offset by -aberrationIntensity*0.1
<feBlend in="GREEN_CHANNEL" in2="BLUE_CHANNEL" mode="screen" result="GB_COMBINED" />
<feBlend in="RED_CHANNEL" in2="GB_COMBINED" mode="screen" result="RGB_COMBINED" />
```
Also ships an actual GLSL-in-canvas shader mode (`shader-utils.ts`, `fragmentShaders.liquidGlass`)
that generates the displacement map instead of a hand-authored SDF, and a **"gel" motion model**:
`calculateDirectionalScale()`/`calculateElasticTranslation()` compute anisotropic squash/stretch
and an elastic translation from cursor distance to the pill's edges, fading in over a 200px
activation zone — this is a pure-Dart-portable interaction model, no shader needed.

**Fidelity.** Medium on optics (real aberration, but the displacement source is still a baked
map); the elastic/gel motion piece is the most complete "fluidity" implementation in this survey.

### archisvaze/liquid-glass — https://github.com/archisvaze/liquid-glass

**Approach.** Interactive demo, **two swappable engines**: `index.html` (SVG `feDisplacementMap`,
Chrome-only, "physics-based displacement map with configurable IOR") and `webgl.html`
(Three.js full-screen shader, "real-time GLSL ray refraction", works in Firefox/Safari too).
Explicit IOR control plus glass thickness/bezel width sliders, specular opacity/saturation,
independent inner/outer shadow, tint. Credits `chakachuk`'s CodePen as the seed for the SVG
filter setup.

**Fidelity.** Medium; useful mainly as evidence that **the WebGL path is what's needed for
cross-browser parity** — the SVG/`feDisplacementMap` route is a Chrome-only dead end on the web,
which is the same reason a Flutter shader (not a platform view) is the right call.

### ALEXalesha/LiquidGlass — https://github.com/ALEXalesha/LiquidGlass

**Approach.** Dependency-free dual implementation (CSS+SVG vs hand-written WebGL2), plus a
Blender/Cycles path-traced reference to check both against, plus a real perf-measurement harness.
Directly names the three things that "decide whether it reads as glass":

1. **Edge profile must be a circular arc**, `h(t) = sqrt(1-(1-t)^2)`, not `smoothstep` — its
   derivative "goes to infinity right at the contour," so compression is sharp at the border and
   gone a few pixels in; a `smoothstep` bump "looks like a highlight, not like glass." (Same
   curve as Kyant0's `circleMap` and kube.io's "convex circle," independently arrived at.)
2. **Displacement scale must be negative** — a convex rim is a lens that pulls in what's
   *outside* the element; positive sign makes it look like a soap bubble.
3. **The highlight is computed, not drawn**: "Blinn-Phong specular from the surface normal of
   the same height field, plus a Fresnel term at the edge and a second, dimmer fill from the
   opposite side" — this is what produces the double rim (bright above, muted below) and lets it
   "wrap around corners by itself."

Engineering notes worth lifting regardless of platform: bakes only **3** textures, not 4
(displacement R/G, rim ring in B, pulled back out via one `feColorMatrix` moving B→alpha — "every
`toDataURL` call costs ~0.9ms flat, whatever the image size"); moved the per-pixel bake into a
Web Worker via `String(fn)` source-sharing; found via a 27,000-case property-based test harness
(`invariants.html`) that "refraction at opposite rims bends opposite ways" and similar physical
invariants are worth asserting in CI, not just eyeballing.

**Fidelity.** High for the *conceptual* model (this is the clearest, most explicit statement in
the whole survey of exactly which three choices make or break the effect), medium for the
shipped code (still bakes a raster displacement map on the CSS/SVG path; only the WebGL2 path is
a live per-pixel shader).

### naughtyduk/liquidGL — https://github.com/naughtyduk/liquidGL

**Approach.** JS library, `engine: "auto"` fallback chain **WebGPU → WebGL2 → WebGL1 → CSS
backdrop-filter**, with its own built-in DOM rasterizer (replaced `html2canvas`, ~54ms median vs
~86ms for a full-page snapshot at `resolution: 2`). Options include `bevelDepth`, `bevelWidth`,
`refraction`, `aberration` (new: "disperses red and blue channels either side of the refraction
vector, blue displaced further than red, matching the way real glass disperses shorter
wavelengths more strongly... concentrates at the bevelled edge and vanishes at the flat centre"),
`tilt`/`tiltFactor`/`tiltEase` (pointer-driven tilt with configurable ease-in/out), sticky-position
tracking, and per-element dirty-tracking so static regions aren't re-rasterized every frame.

**Fidelity.** Medium-high on breadth of features (live video refraction, GSAP integration,
scroll sync); the specific optics are not detailed in the README at the formula level, but the
**perf architecture** (measure-per-frame dirty tracking, engine fallback chain, register only
elements that actually animate) is directly transferable to a Flutter implementation that must
avoid re-rendering a `BackdropFilterLayer` snapshot every frame for static content.

### ybouane/liquidglass (`@ybouane/liquidglass`) — https://github.com/ybouane/liquidglass

**Approach.** WebGL library that renders *every* sibling (not just the backdrop) through an
actual pixel pipeline: static children rasterized once via `html-to-image` (SVG `foreignObject`
clone), `<img>/<canvas>/<video>` drawn directly via `drawImage`, and elements marked
`data-dynamic` re-captured every frame. Each glass element gets an injected `<canvas>` where a
fragment shader applies, in one pass: "refraction, chromatic aberration, Fresnel reflection,
multi-light specular highlights, an inner-stroke rim, and a drop shadow," and **layered
compositing writes each glass canvas back before the next glass runs, so a glass panel above
another sees the lower one in its own refraction** — i.e. glass-on-glass stacking is handled by
sequential compositing rather than a single global shader pass.

Exposed per-element params (defaults) are a good starting point for a Flutter API surface:
`refraction=0.69`, `chromAberration=0.05`, `edgeHighlight=0.05`, `specular=0`, `fresnel=1.0`,
`distortion=0` (noise), `cornerRadius=65px`, `zRadius=40` (bevel depth), `bevelMode` (0 = biconvex
pill, 1 = dome/plano-convex "pair with cornerRadius===zRadius for a half-sphere magnifier"),
`tintStrength`, `shadowOpacity/Spread/OffsetY`.

**Fidelity.** Medium-high; the glass-on-glass compositing order and the explicit "dome vs pill"
bevel-mode split are the most novel ideas here relative to the other sources.

### html-in-canvas.dev — "Liquid Glass Effect in CSS and WebGL" — https://html-in-canvas.dev/liquid-glass-effect/

**Approach.** Tutorial with both a CSS-only version (`backdrop-filter: blur(18px) saturate(1.6)`
+ an SVG turbulence displacement, `baseFrequency=0.008`, 2 octaves, `scale=60`, called out as
*static-only, can't animate*) and a WebGL version with pointer-following "dome" masking:

```
domeRadius = 0.30 * u_hover;
mask = smoothstep(radius, radius*0.08, dist);
refractStrength = 0.06 * dome;   // inward displacement
warp = 0.012 * dome * (simplex(uv*6+t) + simplex(uv*8-t*...));  // organic surface noise
chroma: per-channel scale 1.07 / 1.0 / 0.93, edge term 0.003*dome + 0.007*edge
specular: exponent 28.0, strength 0.40, lightDir = normalize(0.6,-0.45); fresnel exponent 0.55, intensity 0.10
```

**Fidelity.** Medium; useful mainly for concrete numeric starting points (specular exponent,
fresnel exponent, chroma per-channel scale ratios) and for combining simplex noise into the
refraction field for a "liquid" (not perfectly rigid) surface — none of the other sources here
add procedural noise to the bevel itself.

### Oliverrr2424/webgl-apple-liquid-glass — https://github.com/Oliverrr2424/webgl-apple-liquid-glass

**Approach.** By far the most rigorous shader in this survey (`src/v2-shaders.js`,
`FS_GLASS_V2`, WebGL2/GLSL ES 300). Self-described as "squircle SDF thickness field → Snell
refraction with a meniscus rim, dispersion, variable-blur scattering, Fresnel rim." Exposed
material parameters: `refraction: 84`, `edgeReach: 0.14`, `dispersion: 2.0`, `rim: 0.24`,
`reflection: 0.31` (all ratios of element size). Key techniques, with code:

- **Multi-shape field.** Up to `MAX_SHAPES=16` rounded-rects/circles/capsules tracked per
  fragment; each fragment finds its nearest shape (`chosen`) by plain per-shape SDF minimum —
  this is a *selection*, not a blend, of shapes (a `smoothUnion(d1,d2,k)` helper exists in the
  file but is not invoked in the visible per-fragment loop, so true metaball merging across
  *separate* shapes isn't demonstrated in this excerpt — treat it as a building block, not
  evidence of a shipped merge).
- **Rounded-corner normal smoothing** via a `softMax(a,b,k) = 0.5*(a+b+sqrt((a-b)^2+k^2)) - k/2`
  applied only to the SDF's gradient (never to the distance/mask/hairline), because the exact
  `max(q.x,q.y)` distance field has a gradient discontinuity across the corner diagonal, which
  refraction reads as a visible 45° crease.
- **Optical normal ≠ silhouette normal**: the refraction bend uses a *sixth-order superellipse*
  gradient (`g = sign(q)*pow(abs(q),5)/halfSize`) blended in only away from the outer edge
  (`smoothstep(0.12, 0.55, captureX)`), while the visible silhouette keeps the rounded-rect SDF —
  explains why Apple's corners refract smoothly without matching the corner radius exactly.
- **One-sided "capture" exit profile**, `pow(1-captureX, 1.64)`, replacing an earlier
  double-smoothstep that "flattened at the visible contour" and made a captured highlight line
  fold back on itself — a good concrete lesson on why a *monotonic* displacement profile matters
  more than a smooth one.
- **Pre-blur ("frost") composed in quadrature with backdrop blur**:
  `preBlur = sqrt(frostRadius^2 + backdropBlur^2)`, sampled with a 5-tap cross pattern across
  `textureLod` mip levels chosen from `footprintLod` (screen-space derivative-based).
- **Adaptive light/dark contour line**: `interfaceColor()` samples the backdrop just outside and
  just inside the edge, takes `max(luminance, maxChannel*0.72)` (so saturated blue/purple still
  reads as "dark enough"), weights outside 68%/inside 32%, and picks a near-white or near-black
  hairline via `smoothstep(0.40, 0.61, interfaceLight)` — i.e. the light/dark contour is driven
  per-pixel by sampled content, not by a global theme flag.
- **Fresnel/rim**: `key = pow(max(dot(normal,lightDir),0),7) * fresnel`, plus an `opposite` term
  from `-lightDir` at a lower power/weight — the same bright-key/dim-fill double rim ALEXalesha
  describes independently.
- **Press/pinch meniscus**: a per-shape `pressure` term squashes the lens along configurable
  per-axis weights, vanishing at both the center and the silhouette
  (`pressDepth*(1-pressDepth)`), for interactive "pressed glass."
- Linear-light compositing throughout (`linearToSrgb` only at the very end), premultiplied-alpha
  output, and an explicit comment on why the geometric math must run in *uniform control flow*
  before any early-return (derivative/LOD correctness across a fragment quad on real GPUs).

**Fidelity.** Highest of any web source surveyed — the only one that separately models
silhouette vs. optical-normal fields, composes blur radii physically (quadrature), and derives
its rim/hairline color adaptively from sampled content rather than a fixed palette.

### Shadertoy — https://www.shadertoy.com/results?query=Liquid

Multiple community GLSL shaders exist: `3cdXDX` ("Apple liquid glass replicate," 2025-06-11),
`wccSDf` ("Optically correct liquid glass," MetroWind, 2025-06-11), `3clBRH` ("Liquid Glass
without blur," 2025-09-08), `fXX3zr` ("Liquid glass ui," fake lighting + mouse interaction). The
Shadertoy view pages returned HTTP 403 to automated fetches in this session (likely bot
protection), so I could not pull exact GLSL from them; noting them here as leads for manual
follow-up. `carolhsiaoo/awesome-liquid-glass` (https://github.com/carolhsiaoo/awesome-liquid-glass)
is a curated index of these plus most of the other links in this document, worth bookmarking as
the durable index rather than re-searching from scratch next time.

### W3C SVGWG issue #1142 — https://github.com/w3c/svgwg/issues/1142

**Approach.** Standards proposal, not an implementation: web authors currently have no
interoperable way to run `feDisplacementMap` (or any filter) against *live backdrop pixels* — only
against the element's own rendered content — which is precisely why every web source above must
either bake a static displacement PNG (SVG path) or hand-roll a WebGL rasterizer of the DOM. Two
proposed primitives:

```xml
<feDisplacementMap in="BackdropGraphic" in2="map" scale="40"
  xChannelSelector="R" yChannelSelector="G" />

<!-- illustrative higher-level primitive -->
<feRefraction in="BackdropGraphic" radius="24px" thickness="12px"
  indexOfRefraction="1.5" scale="40" />
```

**Relevance.** Confirms by omission that "sample the real composited layer behind you and
refract it in a live shader" — exactly Flutter's `BackdropFilterLayer` + fragment shader model —
is the feature the web platform still lacks and that every JS library above is emulating at a
cost (rasterize-to-canvas, or Chrome-only SVG-as-backdrop-filter). Flutter's existing primitive is
strictly more capable than anything shipping on the web today for this effect.

---

## 3. React Native / Expo

### expo-glass-effect — https://github.com/expo/expo/tree/main/packages/expo-glass-effect

**Wraps native**, does not emulate. `GlassView` renders iOS 26's real `UIVisualEffectView`
(`UIGlassEffect`) — no shader, no displacement math on the JS/native-bridge side at all. iOS
26+ only; falls back to a plain `View` elsewhere. Ships `isLiquidGlassAvailable()`/
`isGlassEffectAPIAvailable()` guards because some iOS 26 betas shipped without the runtime API
despite compiling against the SDK. **Not applicable** to a Flutter shader port beyond confirming
the platform capability-detection pattern (compile-time vs runtime availability can diverge).

### @callstack/liquid-glass — https://github.com/callstack/liquid-glass

**Wraps native** as well: `LiquidGlassView`/`LiquidGlassContainerView` over the real iOS 26
`UIGlassEffect` (requires Xcode ≥ 26, RN ≥ 0.80, not supported in Expo Go). Supports light/dark/
system color-scheme override, `clear`/`regular`/`none` effect variants, tint overlay. Again, no
portable rendering technique — it's a bridge, not an emulation — so it only matters here as a
reminder that **the real API's semantics** (variant names, container-based grouping for
morph/merge) are the ground truth a Flutter shader should visually match, even though the
implementation must be original.

---

## 4. SwiftUI reimplementations / deep-dive reference docs

### conorluddy/LiquidGlassReference — https://github.com/conorluddy/LiquidGlassReference

**Approach.** Not a rendering implementation — a curated, code-example-heavy reference distilled
from Apple's HIG + WWDC25 session 219/356, meant to be handed to an LLM as grounding. Useful for
this survey as a source of *behavioral* ground truth to match, independent of any specific
renderer:

- `GlassEffectContainer` is explicitly the unit that lets shapes "morph individual shapes into
  one another" and is required because **"glass cannot sample other glass"** — i.e. Apple's own
  model also forces a shared backdrop-sampling region for any group of glass elements that must
  visually merge, which is the same constraint a Flutter multi-shape shader would face (§2,
  Oliverrr2424's `MAX_SHAPES` array approach is one way to satisfy it).
- Two material variants only, `.regular` (adapts to any content) and `.clear` (requires a
  dimming layer, only for "bold and bright" foreground content over media) — a two-tier
  adaptivity model simpler than most of the "20 sliders" web ports.
- Accessibility is load-bearing, not cosmetic: `accessibilityReduceTransparency` increases
  frosting, `accessibilityReduceMotion` tones down "parallax effects, specular highlight shifts
  and morphing animations," and iOS 26.1 added a user-facing "Tinted" mode toggle
  independent of both.

### deepraj21/opaline issue #15 — https://github.com/deepraj21/opaline/issues/15

**Approach.** A feature proposal (not yet merged code) for a React glass library to move from
hand-tuned curves to explicit optics: `ior` (default 1.5), `surface` profile enum
(`squircle`/`circle`/`concave`/`lip` — the exact same four profiles as kube.io, independently
named), `thickness` as a multiple of bezel width, Snell's-law lateral shift
`Δ = h · y(t) · tan(θ1 − θ2)`, 128-sample displacement lookup normalized and packed to R/G, scale
= `2·Δmax`. Also proposes a `LiquidGlassProvider` context that sets default optics for a subtree
with per-component override — a provider/inherited-theme pattern directly analogous to an
`InheritedWidget`-based `GlassTheme` in Flutter.

**Fidelity.** Proposal-stage, not shipped; valuable for the API-shape idea (provider-scoped
defaults + Snell's-law-driven, not hand-tuned, displacement) more than for any running code.

---

## 5. Academic / graphics-blog math

### Inigo Quilez — "distfunctions" — https://iquilezles.org/articles/distfunctions/

The canonical reference for combining signed distance fields. Polynomial smooth union:

```glsl
float opSmoothUnion(float a, float b, float k) {
  k *= 4.0;
  float h = max(k - abs(a - b), 0.0);
  return min(a, b) - h*h*0.25/k;
}
float opSmoothSubtraction(float a, float b, float k) { return -opSmoothUnion(a, -b, k); }
```
`k` is the width of the blend region in distance units — this is the exact primitive needed for
"metaball" merging between two nearby glass shapes (the visual the WWDC25 `GlassEffectContainer`
morph relies on) and is cheaper (no `exp`/`log`) than the exponential smooth-min below.

### Alan Zucconi — "Signed Distance Functions" — https://www.alanzucconi.com/2016/07/01/signed-distance-functions/

Ray-marching fundamentals: the conservative-advance loop
(`position += distance(position) * direction`, stepping by the SDF value itself so the ray never
overshoots), basic primitive SDFs (`distance(p,c) - r` for a sphere), and the exponential
smooth-min alternative to Quilez's polynomial:

```glsl
float sdf_smin(float a, float b, float k /* =32 */) {
  float res = exp(-k*a) + exp(-k*b);
  return -log(max(0.0001, res)) / k;
}
```
Not directly needed for a 2D UI-glass shader (no ray marching required for a flat backdrop
lens), but the smooth-min form is the same building block as Quilez's, with a different
performance/smoothness trade-off (C^∞ blend vs. cheaper polynomial).

### Medium — Victor Baro, "SDF in Metal: Adding the Liquid to the Glass" — https://medium.com/@victorbaro/sdf-in-metal-adding-the-liquid-to-the-glass-69abd57e2151

(Fetched via search summary only; page not independently re-verified line-by-line.) Describes
using per-shape SDFs merged with a smooth union inside a Metal fragment shader specifically to
get the "melt together" metaball look for multiple glass blobs — i.e. the same
Quilez/Zucconi math applied end-to-end in a shipping Metal renderer, which is the closest
platform-language analogue (Metal ≈ Impeller's shader backend) to what a Flutter
`FragmentProgram` would need for shape-merge/morph animations.

---

## 6. Convergence check (why the ranking below is not just one library's opinion)

Four independent sources — kube.io (physics derivation), Kyant0/AndroidLiquidGlass (shipping
AGSL), shuding-derived JS ports, and ALEXalesha/LiquidGlass (explicit post-mortem) — all land on
the **same quarter-circle height profile** `h(t) = sqrt(1-(1-t)^2)` / `circleMap(x) = 1-sqrt(1-x²)`
for the bevel, and two independent sources (opaline issue #15, kube.io) name the **same four
surface profiles** (squircle/circle/concave/lip) with the same names. That convergence, reached
from different starting points (one from Snell's law, one from a shipped shader, one from
empirical A/B against a path-traced reference), is the strongest evidence in this survey for
which specific formula to port first.

---

## Techniques ranked for our Flutter package

Ordered by expected fidelity-per-effort. "Shader" = goes in the `FragmentProgram` sampling the
`BackdropFilterLayer`'s snapshot; "Dart" = pure widget/animation code, no shader change.

1. **Quarter-circle bevel profile, not smoothstep** — `d(t) = (1 - sqrt(1-t²)) * refractionAmount`
   where `t` is normalized inward distance from the silhouette SDF. *Fidelity: very high — the
   single biggest "looks like a highlight" vs "looks like glass" switch identified by three
   independent sources.* Shader change: replace whatever falloff curve is currently used for the
   displacement magnitude. **Difficulty: trivial** (one function swap).

2. **Sign of the displacement must pull inward (convex lens), never push outward.** Verify the
   current shader's `grad` direction and displacement sign against Kyant0's
   `setFloatUniform("refractionAmount", -refractionAmount)` convention. *Fidelity: high, cost:
   free.* **Difficulty: trivial.**

3. **Decouple the optical-normal field from the silhouette SDF at rounded corners**
   (Oliverrr2424's `softMax`-smoothed gradient, or a superellipse gradient blended in only away
   from the very edge). Fixes the 45° crease artifact at corners that a raw `max(qx,qy)`
   rounded-rect SDF produces when its gradient feeds refraction directly. *Fidelity: high for
   rounded-rect/squircle shapes specifically.* **Difficulty: medium** (two SDF evaluations per
   fragment instead of one, plus a blend factor).

4. **Adaptive light/dark contour hairline sampled from content**, not a fixed color or a global
   theme flag: sample the backdrop just outside/inside the silhouette, compute a
   luminance-plus-max-channel score, `smoothstep` between a near-black and near-white stroke
   color. *Fidelity: high — this is what makes the rim read correctly over arbitrary wallpapers/
   video without per-scene tuning.* **Difficulty: medium** (2 extra backdrop taps + branch-free
   color mix; already cheap if backdrop is already being sampled for refraction).

5. **Dual-lobe Fresnel/specular rim** (bright key-light term + dimmer opposite-side fill term
   from the same normal field) rather than a single rim light. *Fidelity: high for motion
   response — this is what makes the highlight "wrap around" the silhouette and answers the
   brief's "highlight direction and motion response" requirement when the light direction is fed
   from device orientation.* **Difficulty: low-medium** (two `pow(dot(N,L),k)` terms instead of
   one; device-orientation-driven `L` is a Dart-side concern, not shader).

6. **Chromatic aberration as a radially-growing per-channel sample offset**, concentrated at the
   bevel and ~zero at the flat center (naughtyduk's "blue displaced further than red," or
   Kyant0's 7-tap spectral sweep for higher quality). Start with the cheap 3-tap R/G/B version;
   reserve the 7-tap sweep for a "high quality" flag. *Fidelity: medium-high, mostly cosmetic
   polish.* **Difficulty: medium** (3–7 extra backdrop samples per fragment; watch fragment
   shader cost on lower-end GPUs — this is the first candidate to gate behind a quality tier).

7. **Physically composed blur radii** — `pre-blur ⊕ backdrop-blur = sqrt(a² + b²)` (quadrature
   sum) instead of applying two independent blur passes — so a "frosted" material setting and a
   host-supplied backdrop blur combine correctly instead of double-blurring or fighting each
   other. *Fidelity: medium, mostly correctness rather than a visible new effect.*
   **Difficulty: low** (one extra `sqrt`, assuming the shader already picks a mip/LOD or does a
   multi-tap blur for the backdrop sample).

8. **Multi-shape shared backdrop + smooth-union (metaball) merge for `GlassEffectContainer`-style
   morphing** — a small fixed-size array of shape descriptors (center, half-size, corner radius,
   type) in the shader, per-fragment nearest-shape or Quilez `opSmoothUnion(d1,d2,k)` blend
   across shapes whose bounds are close enough to interact. This is the mechanism needed for
   Apple's HIG requirement that "glass cannot sample other glass" — instead, a group of glass
   widgets must share one sampling/merge pass. *Fidelity: high, but only matters once the package
   supports animated grouping/morphing between adjacent glass widgets — it's a feature, not a
   polish pass.* **Difficulty: high** (uniform array plumbing from Dart, shader branching over N
   shapes, and the Dart-side layout code to decide which widgets are "close enough" to merge each
   frame).

9. **Press/pinch meniscus squash** — an interaction-driven per-axis inward displacement term
   that vanishes at both the shape's center and its silhouette (so it never inflates the rim),
   used for tap/press feedback instead of a generic scale-down. *Fidelity: medium, nice-to-have
   interaction polish ("interactive press shimmer" in the brief).* **Difficulty: medium** (one
   more displacement term gated by an `AnimationController`-driven pressure uniform).

10. **Elastic "gel" motion response** (anisotropic squash/stretch + elastic translation toward
    the cursor/touch point, fading in over an activation distance) — this is pure Dart
    (`Transform`, `AnimatedContainer`/`Tween`), not a shader concern, and is the most complete
    implementation of "fluidity" found in the survey (rdev/liquid-glass-react). *Fidelity:
    medium-high for perceived "liquid" feel, zero shader cost.* **Difficulty: low** (widget-tree
    transform math only).

11. **Snell's-law-parameterized authoring API** (`ior`, `thickness`, `surface: squircle|circle|
    concave|lip`) instead of exposing raw shader constants, computing the displacement curve
    from real refraction geometry the way kube.io and the opaline proposal do. *Fidelity: neutral
    on pixels (same curve family as #1 if implemented correctly) but high value for a public
    Flutter package API — designers can reason about "index of refraction" and "thickness"
    instead of tuning opaque floats.* **Difficulty: medium** (math substitution behind the
    existing uniforms, plus API/docs work).

12. **Dirty-region / cache-when-static backdrop capture**, avoiding re-running the shader (or
    even re-snapshotting the `BackdropFilterLayer`) for glass panels whose backdrop hasn't
    changed since the last frame (naughtyduk's per-element dirty tracking; ybouane's
    `data-dynamic`-vs-cached split). *Fidelity: N/A (perf only), but likely necessary — every web
    source that measured performance found backdrop capture/rasterization, not the shader math,
    was the dominant cost.* **Difficulty: medium-high** (needs a way to detect "the layer behind
    this widget repainted" in Flutter's pipeline, which is less directly observable than in a
    DOM `MutationObserver`).

---

## Sources index

| # | Source | URL |
|---|---|---|
| 1 | Kyant0/AndroidLiquidGlass | https://github.com/Kyant0/AndroidLiquidGlass |
| 2 | kube.io — Liquid Glass in the Browser | https://kube.io/blog/liquid-glass-css-svg/ |
| 3 | shuding/liquid-glass | https://github.com/shuding/liquid-glass |
| 4 | rdev/liquid-glass-react | https://github.com/rdev/liquid-glass-react |
| 5 | archisvaze/liquid-glass | https://github.com/archisvaze/liquid-glass |
| 6 | ALEXalesha/LiquidGlass | https://github.com/ALEXalesha/LiquidGlass |
| 7 | naughtyduk/liquidGL | https://github.com/naughtyduk/liquidGL |
| 8 | ybouane/liquidglass | https://github.com/ybouane/liquidglass |
| 9 | html-in-canvas.dev article | https://html-in-canvas.dev/liquid-glass-effect/ |
| 10 | Oliverrr2424/webgl-apple-liquid-glass | https://github.com/Oliverrr2424/webgl-apple-liquid-glass |
| 11 | Shadertoy "Liquid" results | https://www.shadertoy.com/results?query=Liquid |
| 12 | carolhsiaoo/awesome-liquid-glass (index) | https://github.com/carolhsiaoo/awesome-liquid-glass |
| 13 | W3C SVGWG issue #1142 | https://github.com/w3c/svgwg/issues/1142 |
| 14 | expo-glass-effect | https://github.com/expo/expo/tree/main/packages/expo-glass-effect |
| 15 | @callstack/liquid-glass | https://github.com/callstack/liquid-glass |
| 16 | conorluddy/LiquidGlassReference | https://github.com/conorluddy/LiquidGlassReference |
| 17 | deepraj21/opaline issue #15 | https://github.com/deepraj21/opaline/issues/15 |
| 18 | Inigo Quilez — distfunctions | https://iquilezles.org/articles/distfunctions/ |
| 19 | Alan Zucconi — Signed Distance Functions | https://www.alanzucconi.com/2016/07/01/signed-distance-functions/ |
| 20 | Victor Baro (Medium) — SDF in Metal | https://medium.com/@victorbaro/sdf-in-metal-adding-the-liquid-to-the-glass-69abd57e2151 |

## Gaps / not independently verified

- Shadertoy shader bodies (`wccSDf`, `3cdXDX`, `3clBRH`, `fXX3zr`) — page fetches returned HTTP
  403; only titles/authorship/dates from search results, not verified GLSL.
- Medium "SDF in Metal" article — summarized from a tool's page-read, not cross-checked against
  a second fetch.
- Kyant0's GitBook (`kyant.gitbook.io/backdrop`) — not fetched; likely has more architectural
  detail than the README.
