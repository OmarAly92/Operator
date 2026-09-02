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
	align-items: center;
	gap: 8px;
	height: 24px;
	/* The block's own padding supplies the inset now. Warp's middle padding is the
	   0.5-line gap between the command and its output. */
	padding: 0;
	margin-bottom: calc(var(--terminal-line-height) * 0.5);
	border-bottom: 1px solid var(--terminal-block-border);
	color: var(--terminal-block-header-foreground);
	font-size: 12px;
	white-space: nowrap;
	overflow: hidden;
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
	flex: 1 1 auto;
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

.terminal-block-branch::before {
	content: "";
}

/* The transcript is text the user copies out of, and a desktop shell that turns
   selection off app-wide -- the usual convention, so a drag on chrome does not
   paint it blue -- otherwise takes that with it. Selection is what the copy
   actions and getSelectionRange() are for, so the package asserts it rather
   than depending on the host to make an exception for us. */
.terminal-block,
.terminal-alt-surface {
	-webkit-user-select: text;
	user-select: text;
}

/* Warp paints the selection as a rectangle per row, the full height of the row
   and out to its end, behind the glyph and leaving the text its own colour. The
   browser instead paints the glyph box: narrower than the row and shorter than
   the line, so rows come out ragged with gaps between them. The renderer paints
   the row backgrounds itself (selection-fill.ts) and the browser's own highlight
   is turned off so the two cannot disagree. */
.terminal-block ::selection,
.terminal-block::selection,
.terminal-alt-surface ::selection,
.terminal-alt-surface::selection {
	background-color: transparent;
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

.terminal-run {
	color: inherit;
}

.terminal-block-actions {
	position: absolute;
	top: 4px;
	right: 8px;
	display: none;
	gap: 4px;
	pointer-events: auto;
}

.terminal-block:hover .terminal-block-actions,
.terminal-block:focus-within .terminal-block-actions {
	display: inline-flex;
}

.terminal-block-action {
	font: inherit;
	font-size: 11px;
	line-height: 1;
	padding: 2px 6px;
	color: var(--terminal-block-header-foreground);
	background: var(--terminal-block-background);
	border: 1px solid var(--terminal-block-border);
	border-radius: 3px;
	cursor: pointer;
	opacity: 0.85;
}

.terminal-block-action:hover,
.terminal-block-action:focus-visible {
	opacity: 1;
	outline: 1px solid var(--terminal-block-header-foreground);
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
	left: 0;
	right: 0;
	z-index: 2;
	pointer-events: none;
	box-sizing: border-box;
	display: flex;
	align-items: center;
	gap: 8px;
	height: 24px;
	padding: 0 8px;
	border-bottom: 1px solid var(--terminal-block-border);
	background: var(--terminal-block-background);
	color: var(--terminal-block-header-foreground);
	font-family: var(--terminal-font-family);
	font-size: 12px;
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
