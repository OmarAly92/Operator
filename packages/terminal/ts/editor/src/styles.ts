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

.terminal-editor[aria-readonly="true"] {
	opacity: 0.72;
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
}`;
