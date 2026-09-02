export const editorStyles = `.terminal-editor {
	box-sizing: border-box;
	width: 100%;
	min-height: var(--terminal-line-height, 20px);
	padding: 4px 8px;
	color: var(--terminal-foreground);
	background: var(--terminal-background);
	font-family: var(--terminal-font-family);
	font-size: var(--terminal-font-size);
	font-weight: var(--terminal-font-weight);
	letter-spacing: var(--terminal-letter-spacing);
	line-height: var(--terminal-line-height);
	font-variant-ligatures: var(--terminal-ligatures);
	white-space: pre;
	outline: none;
}

/* Empty while the child owns the line, so it must not reserve a row's worth of
   space at the bottom of the pane. It stays focusable: zero height still takes
   focus, where display:none or visibility:hidden would refuse it and the
   keystrokes would go nowhere. */
.terminal-editor[aria-readonly="true"] {
	min-height: 0;
	padding: 0;
}

.terminal-editor-line {
	min-height: var(--terminal-line-height, 20px);
}

.terminal-editor-caret {
	color: var(--terminal-background);
	background: var(--terminal-cursor);
}

.terminal-editor:not(:focus) .terminal-editor-caret {
	color: inherit;
	background: transparent;
	border-bottom: 1px solid var(--terminal-cursor);
}

.terminal-editor-token[data-token-kind="command"] {
	color: var(--terminal-ansi-4);
}

.terminal-editor-token[data-token-kind="flag"] {
	color: var(--terminal-ansi-3);
}

.terminal-editor-token[data-token-kind="string"] {
	color: var(--terminal-ansi-2);
}

.terminal-editor-token[data-token-kind="operator"] {
	color: var(--terminal-ansi-5);
}

.terminal-editor-token[data-token-kind="path"],
.terminal-editor-token[data-token-kind="variable"] {
	color: var(--terminal-ansi-6);
}

.terminal-editor-token[data-token-kind="comment"] {
	color: var(--terminal-ansi-8);
}

.terminal-editor-ghost {
	color: var(--terminal-ansi-8);
	opacity: 0.72;
}

.terminal-editor-search {
	padding-bottom: 4px;
	color: var(--terminal-ansi-6);
}

.terminal-editor-prompt {
	display: flex;
	gap: 8px;
	align-items: baseline;
	padding-bottom: 4px;
}

.terminal-editor-prompt-cwd {
	color: var(--terminal-ansi-4);
}

.terminal-editor-prompt-branch {
	color: var(--terminal-ansi-5);
}

.terminal-editor-prompt-marker {
	color: var(--terminal-ansi-2);
}

.terminal-editor-prompt[data-last-exit]:not([data-last-exit="0"]) .terminal-editor-prompt-marker {
	color: var(--terminal-ansi-1);
}

.terminal-completions {
	padding: 4px 0;
	color: var(--terminal-foreground);
	background: var(--terminal-background);
	border: 1px solid var(--terminal-ansi-8);
}

.terminal-completion-row {
	display: flex;
	gap: 8px;
	padding: 2px 8px;
	color: var(--terminal-foreground);
}

.terminal-completion-row[data-selected="true"] {
	background: var(--terminal-selection);
	color: var(--terminal-background);
}

.terminal-completion-row[data-selected="true"] .terminal-completion-description {
	color: var(--terminal-background);
}

.terminal-completion-match {
	color: var(--terminal-ansi-3);
	font-weight: var(--terminal-font-weight);
}

.terminal-completion-row[data-selected="true"] .terminal-completion-match {
	color: var(--terminal-background);
}

.terminal-completion-description {
	color: var(--terminal-ansi-8);
}`;
