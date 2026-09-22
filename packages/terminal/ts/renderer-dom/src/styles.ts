export const terminalStyles = `@font-face {
	font-family: "Hack";
	src: url("./fonts/hack-regular.woff2") format("woff2");
	font-weight: 400;
	font-style: normal;
	font-display: swap;
}

@font-face {
	font-family: "Hack";
	src: url("./fonts/hack-bold.woff2") format("woff2");
	font-weight: 700;
	font-style: normal;
	font-display: swap;
}

@font-face {
	font-family: "Hack";
	src: url("./fonts/hack-italic.woff2") format("woff2");
	font-weight: 400;
	font-style: italic;
	font-display: swap;
}

@font-face {
	font-family: "Hack";
	src: url("./fonts/hack-bolditalic.woff2") format("woff2");
	font-weight: 700;
	font-style: italic;
	font-display: swap;
}

.terminal-surface {
	box-sizing: border-box;
	/* A column so the host takes the space the line editor leaves. With the host
	   at height:100% the editor was laid out past the surface's bottom edge, the
	   pane clipped the overflow, and the first row of the transcript was cut off
	   with no way to scroll up to it. */
	display: flex;
	flex-direction: column;
	height: 100%;
	width: 100%;
	/* Nothing here: the whole horizontal inset is Warp's PADDING_LEFT
	   (app/src/terminal/view.rs = 16), and .terminal-block carries it. A hairline
	   here as well would stack on top of that and put the content at 20px.
	   Vertically the pane stays flush; the block's own padding does that work. */
	--terminal-padding-x: 0px;
	--terminal-padding-y: 0px;
	padding: var(--terminal-padding-y) var(--terminal-padding-x);
}

.terminal-host {
	flex: 1 1 auto;
	/* Without this the flex item refuses to shrink below its content height, so
	   the scroll container never forms and the overflow returns. */
	min-height: 0;
	width: 100%;
	background: var(--terminal-background);
	display: flex;
	flex-direction: column;
}

/* Warp anchors its blocks to the bottom of the pane: the first command you run
   appears at the bottom edge and earlier output scrolls up off the top. An auto
   top margin does that without breaking the scroller -- it absorbs the spare
   space when the content is short and resolves to zero once the content
   overflows. justify-content: flex-end would overflow past the top of the
   scroll box instead, putting the earliest output out of reach. */
.terminal-list {
	flex: 0 0 auto;
	margin-top: auto;
}

.terminal-editor-host {
	flex: 0 0 auto;
}

/* The host carries tabindex=0 only while the alt-screen key handler is bound.
   That focus is an implementation detail of input routing, not a control the
   user is tabbing through, so it must not paint the UA focus ring around the
   whole terminal body -- it reads as "the terminal is selected". xterm.js
   resets its own .xterm:focus outline for the same reason. */
.terminal-host:focus,
.terminal-host:focus-visible {
	outline: none;
}

.terminal-alt-slot {
	height: 100%;
	width: 100%;
}

.terminal-block {
	background: var(--terminal-block-background);
	color: var(--terminal-foreground);
	/* Warp's BlockPadding in grid cells (app/src/settings/mod.rs,
	   TerminalSpacing::normal: 1.1 lines above, 1 line below) and the terminal
	   view's 16px horizontal inset (app/src/terminal/view.rs, PADDING_LEFT).
	   block-metrics.ts carries the same numbers so the virtualiser reserves the
	   height this reserves -- change them together. */
	padding: calc(var(--terminal-line-height) * 1.1) 16px calc(var(--terminal-line-height) * 1);
	/* A rule between blocks, not a box around each one -- this mirrors Warp's
	   draw_border_between_blocks (gated on show_block_dividers, default true).
	   A full border plus a radius is what made the pane read as boxy. */
	border-top: 1px solid var(--terminal-block-border);
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: var(--terminal-font-weight);
	letter-spacing: var(--terminal-letter-spacing);
	line-height: var(--terminal-line-height);
	font-variant-ligatures: var(--terminal-ligatures);
	white-space: pre;
}

.terminal-block-header {
	box-sizing: border-box;
	display: flex;
	flex-direction: column;
	height: calc(var(--terminal-line-height) * 2);
	padding: 0;
	margin-bottom: calc(var(--terminal-line-height) * 0.5);
	color: var(--terminal-block-header-foreground);
	font-size: inherit;
	white-space: nowrap;
	overflow: hidden;
}

.terminal-block-metadata {
	display: flex;
	align-items: center;
	gap: 8px;
	min-width: 0;
	height: var(--terminal-line-height);
	font-size: 0.85em;
}

.terminal-block-header[data-block-status="plain"] {
	display: none;
}

.terminal-block-status-dot {
	width: 8px;
	height: 8px;
	border-radius: 50%;
	flex: 0 0 auto;
	background: var(--terminal-ansi-8);
}

.terminal-block-header[data-block-status="running"] .terminal-block-status-dot {
	background: var(--terminal-ansi-3);
}

.terminal-block-header[data-block-status="succeeded"] .terminal-block-status-dot {
	background: var(--terminal-ansi-2);
}

.terminal-block-header[data-block-status="failed"] .terminal-block-status-dot {
	background: var(--terminal-ansi-1);
}

.terminal-block-header[data-block-status="abandoned"] .terminal-block-status-dot {
	background: var(--terminal-ansi-8);
}

.terminal-block-command {
	display: block;
	color: var(--terminal-foreground);
	font-weight: 700;
	height: var(--terminal-line-height);
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
}

.terminal-block-cwd,
.terminal-block-branch,
.terminal-block-duration,
.terminal-block-exit {
	flex: 0 0 auto;
	color: var(--terminal-block-header-foreground);
	opacity: 0.75;
}

.terminal-block-cwd,
.terminal-block-branch {
	flex: 0 1 auto;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
}

.terminal-block-exit {
	margin-left: 8px;
}

.terminal-block-branch::before {
	content: "";
}

.terminal-block,
.terminal-alt-surface {
	-webkit-user-select: none;
	user-select: none;
	cursor: default;
}

/* The hand appears only while a link is under the pointer, the way Warp swaps
   the cursor shape per hovered link (app/src/terminal/view.rs set_cursor_shape
   Cursor::PointingHand / reset_cursor; app/src/util/link_detection.rs). */
.terminal-link-hover .terminal-block,
.terminal-link-hover .terminal-alt-surface {
	cursor: pointer;
}

.terminal-decorations,
.terminal-decorations [data-terminal-layer] {
	position: absolute;
	top: 0;
	left: 0;
	width: 0;
	height: 0;
	overflow: visible;
	pointer-events: none;
}

.terminal-decorations {
	z-index: 2;
}

.terminal-decorations [data-terminal-layer] > div {
	position: absolute;
	box-sizing: border-box;
}

.terminal-link-underline {
	border-bottom: 1px solid var(--terminal-foreground);
}

/* Alacritty paints a hint's match and its label over the cells the match
   occupies (alacritty/src/display/hint.rs, HintState::labels); the label sits
   at the match's first cell so the eye reads label-then-text. */
.terminal-hint-match {
	background: var(--terminal-selection);
}

.terminal-hint-label {
	display: flex;
	align-items: center;
	padding: 0 2px;
	width: auto;
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: 700;
	line-height: var(--terminal-line-height);
	color: var(--terminal-background);
	background: var(--terminal-ansi-3);
}

/* A masked secret is painted over its cells rather than rewritten into the row,
   so the model keeps the bytes and only what is READ is masked (Warp
   crates/warp_terminal/src/model/secrets.rs, RespectObfuscatedSecrets). */
.terminal-redaction {
	background: var(--terminal-foreground);
	opacity: 0.85;
}

/* warp/crates/warp_terminal/src/model/grid/grid_renderer.rs draws provisional
   text at reduced alpha so it reads as not-yet-confirmed. */
.terminal-prediction {
	position: absolute;
	pointer-events: none;
	opacity: 0.45;
	font: inherit;
	line-height: var(--terminal-line-height);
	color: var(--terminal-foreground);
}

/* Chrome stays unselectable, so dragging across a block picks up its output and
   not the header metadata or the labels of the buttons floating over it. */
.terminal-block-header,
.terminal-block-actions,
.terminal-pinned-header,
.terminal-jump-to-bottom,
.terminal-find-bar,
.terminal-palette {
	-webkit-user-select: none;
	user-select: none;
	cursor: default;
}

.terminal-row {
	position: relative;
	z-index: 0;
	display: block;
	min-height: var(--terminal-line-height);
}

/* Warp fills the cursor cell with the theme cursor colour -- the accent, unless
   a theme overrides it -- behind the glyph, then lifts the glyph's contrast
   against it (grid_renderer.rs, cell_colors). Painting the block on top of the
   glyph instead hides the character the user is about to overwrite, which is
   the whole point of the cursor. The row is a stacking context so the negative
   z-index goes behind its own text without falling behind the block's
   background. */
.terminal-cursor {
	position: absolute;
	top: 0;
	left: 0;
	z-index: -1;
	height: var(--terminal-line-height);
	background: var(--terminal-cursor);
	pointer-events: none;
}

/* Below MIN_CURSOR_CONTRAST the cursor takes the foreground and its glyph the
   background (alacritty/src/display/content.rs:124-134); it rises above the
   run to carry that glyph, as xterm.js's DOM block cursor does
   (src/browser/renderer/dom/DomRendererRowFactory.ts, xterm-cursor-block).
   Unfocused, a hollow block (ghostty/src/renderer/cursor.zig:58-60; Warp
   HollowBlock, app/src/terminal/grid_renderer.rs:2471). */
.terminal-cursor-inverted {
	z-index: 1;
	background: var(--terminal-foreground);
	color: var(--terminal-background);
	white-space: pre;
}

.terminal-cursor-hollow {
	background: transparent;
	box-shadow: inset 0 0 0 1px var(--terminal-cursor);
}

.terminal-cursor-inverted.terminal-cursor-hollow {
	color: inherit;
	box-shadow: inset 0 0 0 1px var(--terminal-foreground);
}

/* IME marked text over the cursor cell, underlined as Warp draws it
   (app/src/terminal/grid_renderer.rs:657-675); positioned like xterm.js's
   composition-view (css/xterm.css:79-91). */
.terminal-composition-view {
	position: absolute;
	display: none;
	z-index: 2;
	pointer-events: none;
	white-space: pre;
	font: inherit;
	color: var(--terminal-foreground);
	background: var(--terminal-background);
	text-decoration: underline;
	text-decoration-thickness: 0.09em;
}

.terminal-composition-view.active {
	display: inline-block;
}

.terminal-run {
	display: inline-block;
	vertical-align: top;
	height: var(--terminal-line-height);
	color: inherit;
}

/* SGR decorations, drawn only when RendererFeatures.attributes is "warp".
   Thickness follows Warp's UNDERLINE_THICKNESS_SCALE_FACTOR = 0.15 of the
   cell width (app/src/terminal/grid_renderer.rs:52,2352); Hack's advance is
   0.6em, so 0.09em. Blink gets a class and no animation: Warp's
   ansi_handler.rs terminal_attribute has no Blink arm. */
.terminal-run[data-italic] {
	font-style: italic;
}

.terminal-run[data-hidden] {
	visibility: hidden;
}

.terminal-run[data-underline] {
	text-decoration-thickness: 0.09em;
	text-decoration-color: var(--terminal-underline, currentColor);
}

.terminal-run[data-underline="double"] {
	text-decoration-style: double;
}

.terminal-run[data-underline="curly"] {
	text-decoration-style: wavy;
}

.terminal-run[data-underline="dotted"] {
	text-decoration-style: dotted;
}

.terminal-run[data-underline="dashed"] {
	text-decoration-style: dashed;
}

.terminal-run[data-decor="u"] {
	text-decoration-line: underline;
}

.terminal-run[data-decor="s"] {
	text-decoration-line: line-through;
}

.terminal-run[data-decor="o"] {
	text-decoration-line: overline;
}

.terminal-run[data-decor="us"] {
	text-decoration-line: underline line-through;
}

.terminal-run[data-decor="uo"] {
	text-decoration-line: underline overline;
}

.terminal-run[data-decor="so"] {
	text-decoration-line: line-through overline;
}

.terminal-run[data-decor="uso"] {
	text-decoration-line: underline line-through overline;
}

/* Block elements (U+2580..U+259F) are drawn as cell-filling rectangles rather
   than from the font. A font glyph fills one em, the row box is line-height,
   and CSS splits the difference as half-leading -- so stacked blocks show a
   seam on every row. Warp draws its box-drawing range procedurally for the
   same reason (grid_renderer/box_drawing.rs, BoxDrawingGlyphs). The character
   stays in the DOM, transparent, so selection and copy still see it. */
.terminal-block-glyph {
	position: relative;
	display: inline-block;
	vertical-align: top;
	height: var(--terminal-line-height);
	color: transparent;
	letter-spacing: 0;
}

.terminal-block-glyph > i {
	position: absolute;
}

.terminal-alt-surface {
	position: relative;
	height: 100%;
	width: 100%;
	white-space: pre;
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: var(--terminal-font-weight);
	letter-spacing: var(--terminal-letter-spacing);
	line-height: var(--terminal-line-height);
	font-variant-ligatures: var(--terminal-ligatures);
	color: var(--terminal-foreground);
	background: var(--terminal-background);
}

.terminal-alt-cursor {
	position: absolute;
	width: 1ch;
	height: var(--terminal-line-height);
	background: var(--terminal-cursor);
	opacity: 0.8;
}

.terminal-find-bar {
	position: absolute;
	top: 8px;
	right: 16px;
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 4px 8px;
	background: var(--terminal-block-background);
	border: 1px solid var(--terminal-block-border);
	border-radius: 4px;
	color: var(--terminal-block-header-foreground);
	font-family: var(--terminal-font-family);
	font-size: 12px;
	z-index: 4;
}

.terminal-find-label {
	display: inline-flex;
	align-items: center;
}

.terminal-find-input {
	font: inherit;
	font-size: 12px;
	color: var(--terminal-block-header-foreground);
	background: var(--terminal-background);
	border: 1px solid var(--terminal-block-border);
	border-radius: 3px;
	padding: 2px 6px;
	min-width: 180px;
	outline: none;
}

.terminal-find-input:focus-visible {
	border-color: var(--terminal-block-header-foreground);
}

.terminal-find-count {
	font-size: 11px;
	color: var(--terminal-block-header-foreground);
	opacity: 0.85;
	min-width: 64px;
	text-align: right;
}

.terminal-find-row-match {
	background: var(--terminal-selection);
}

.terminal-find-row-active {
	outline: 1px solid var(--terminal-cursor);
	outline-offset: -1px;
}

.terminal-pinned-header {
	position: sticky;
	top: 0;
	z-index: 2;
	pointer-events: none;
	box-sizing: border-box;
	display: flex;
	flex: 0 0 auto;
	flex-direction: column;
	height: calc(var(--terminal-line-height) * 2 + 17px);
	margin-bottom: calc(var(--terminal-line-height) * -2 - 17px);
	padding: 8px 16px;
	border-bottom: 1px solid var(--terminal-block-border);
	background: var(--terminal-block-background);
	color: var(--terminal-block-header-foreground);
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	line-height: var(--terminal-line-height);
	white-space: nowrap;
	overflow: hidden;
}

.terminal-pinned-header[data-block-status="plain"] {
	display: none;
}

.terminal-pinned-header[hidden] {
	display: none;
}

.terminal-block-focused {
	border-color: var(--terminal-block-header-foreground);
	outline: 1px solid var(--terminal-block-header-foreground);
	outline-offset: -1px;
}`;

const terminalFontUrls: Record<string, string> = {
	"hack-regular.woff2": new URL("../src/fonts/hack-regular.woff2", import.meta.url).href,
	"hack-bold.woff2": new URL("../src/fonts/hack-bold.woff2", import.meta.url).href,
	"hack-italic.woff2": new URL("../src/fonts/hack-italic.woff2", import.meta.url).href,
	"hack-bolditalic.woff2": new URL("../src/fonts/hack-bolditalic.woff2", import.meta.url).href,
};

export function terminalStylesForDocument(): string {
	return terminalStyles.replace(/url\("\.\/fonts\/([^"]+)"\)/g, (_match, filename: string) => {
		return `url("${terminalFontUrls[filename]}")`;
	});
}
