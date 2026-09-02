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
	/* A 4px hairline left and right so glyphs do not touch the pane edge, and
	   nothing vertically -- the first and last lines sit flush against the pane.
	   Warp's own BlockPadding pads nothing horizontally, and the 16px this
	   replaced cost ~3 columns a line. */
	--terminal-padding-x: 4px;
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
	padding: 0 8px;
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

.terminal-row {
	display: block;
	min-height: var(--terminal-line-height);
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
