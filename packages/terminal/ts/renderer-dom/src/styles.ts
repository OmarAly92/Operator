export const terminalStyles = `.terminal-block {
	background: var(--terminal-block-background);
	color: var(--terminal-foreground);
	border: 1px solid var(--terminal-block-border);
	border-radius: 4px;
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

.terminal-row {
	display: block;
	min-height: var(--terminal-line-height);
}

.terminal-run {
	color: inherit;
}
`;
