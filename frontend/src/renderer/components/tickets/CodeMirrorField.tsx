import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { Annotation, EditorState } from "@codemirror/state";
import { EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from "@codemirror/view";
import { useEffect, useRef } from "react";

const editorTheme = EditorView.theme(
	{
		"&": {
			height: "100%",
			backgroundColor: "var(--color-bg-terminal-opaque)",
			color: "var(--color-text-primary)",
			fontSize: "12.5px",
		},
		".cm-scroller": { fontFamily: "var(--font-family-mono)", lineHeight: "1.6", overflow: "auto" },
		".cm-content": { padding: "12px 0", caretColor: "var(--color-text-primary)" },
		".cm-line": { padding: "0 16px" },
		".cm-gutters": {
			backgroundColor: "transparent",
			color: "var(--color-text-passive)",
			border: "none",
			paddingLeft: "8px",
		},
		".cm-activeLine, .cm-activeLineGutter": { backgroundColor: "var(--color-interactive-hover)" },
		"&.cm-focused": { outline: "none" },
		".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
			backgroundColor: "var(--color-interactive-hover)",
		},
		".cm-cursor": { borderLeftColor: "var(--color-text-primary)" },
	},
	{ dark: true },
);

const externalChange = Annotation.define<boolean>();

type Callbacks = {
	onChange: (next: string) => void;
	onSave: () => void;
	onTopLineChange?: (line: number) => void;
};

function topLine(view: EditorView): number {
	const rect = view.scrollDOM.getBoundingClientRect();
	const pos = view.posAtCoords({ x: rect.left + 1, y: rect.top + 1 }, false);
	return view.state.doc.lineAt(pos).number;
}

export function CodeMirrorField({
	value,
	onChange,
	onSave,
	onTopLineChange,
	ariaLabel,
	autoFocus = false,
}: Callbacks & { value: string; ariaLabel: string; autoFocus?: boolean }) {
	const host = useRef<HTMLDivElement>(null);
	const viewRef = useRef<EditorView | null>(null);
	const callbacks = useRef<Callbacks>({ onChange, onSave, onTopLineChange });
	callbacks.current = { onChange, onSave, onTopLineChange };
	const initialValue = useRef(value);

	useEffect(() => {
		const parent = host.current;
		if (!parent) return;
		const state = EditorState.create({
			doc: initialValue.current,
			extensions: [
				lineNumbers(),
				highlightActiveLine(),
				highlightActiveLineGutter(),
				history(),
				markdown(),
				EditorView.lineWrapping,
				keymap.of([
					{
						key: "Mod-s",
						preventDefault: true,
						run: () => {
							callbacks.current.onSave();
							return true;
						},
					},
					...defaultKeymap,
					...historyKeymap,
				]),
				EditorView.updateListener.of((update) => {
					if (!update.docChanged) return;
					if (update.transactions.some((transaction) => transaction.annotation(externalChange))) return;
					callbacks.current.onChange(update.state.doc.toString());
				}),
				EditorView.domEventHandlers({
					scroll: (_event, view) => {
						callbacks.current.onTopLineChange?.(topLine(view));
						return false;
					},
				}),
				EditorView.contentAttributes.of({ "aria-label": ariaLabel }),
				editorTheme,
			],
		});
		const view = new EditorView({ state, parent });
		viewRef.current = view;
		return () => {
			view.destroy();
			viewRef.current = null;
		};
	}, [ariaLabel]);

	useEffect(() => {
		if (autoFocus) viewRef.current?.focus();
	}, [autoFocus]);

	useEffect(() => {
		const view = viewRef.current;
		if (!view) return;
		const current = view.state.doc.toString();
		if (current === value) return;
		view.dispatch({ changes: { from: 0, to: current.length, insert: value }, annotations: externalChange.of(true) });
	}, [value]);

	return <div ref={host} className="min-h-0 flex-1 overflow-hidden [&_.cm-editor]:h-full" data-testid="codemirror-field" />;
}
