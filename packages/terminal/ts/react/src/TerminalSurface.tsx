import { useCallback, useLayoutEffect, useRef, useState, type ReactElement, type ReactNode } from "react";
import { clipboardHasImage, deliverPaste, encodeKey, LineEditor, planPaste } from "@operator/terminal-editor";
import {
	createFindBar,
	createPathProvider,
	DEFAULT_LINK_PROVIDERS,
	DomBlockRenderer,
	RERUN_EVENT,
	resolveFeatures,
	type BlockFinishedEvent,
	type FindBar,
	type HintEvent,
	type MarkRule,
	type RendererFeatures,
} from "@operator/terminal-renderer-dom";
import { isCopyChord } from "./selection-gesture.js";
import {
	anchorFromElement,
	createCompositionTarget,
	decodeBlocks,
	defaultStrings,
	type CompositionTarget,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { AltScreenSlot } from "./AltScreenSlot.js";
import { isMacPlatform } from "./surface-geometry.js";
import { useSurfaceInput } from "./use-surface-input.js";

export interface TerminalSurfaceProps {
	core: TerminalCore;
	theme: TerminalTheme;
	font: FontConfig;
	className?: string;
	altScreenSurface?: ReactNode;
	altScreenActive: boolean;
	host?: HostCapabilities;
	strings?: TerminalStrings;
	onSend(text: string): void;
	onSendRaw(data: string): void;
	onGeometry?: (columns: number, rows: number) => void;
	/**
	 * Bump to force the surface to re-derive its grid from the live box.
	 *
	 * The ResizeObserver below is the steady-state path, but it only reports
	 * changes it observes. A host that moves this surface between containers --
	 * a retained-terminal cache parking a pane off screen and showing it again --
	 * can change the layout under a box the observer sees as unchanged, leaving
	 * the grid sized for a pane the surface no longer occupies.
	 *
	 * Warp has no equivalent hook because it does not need one: its terminal view
	 * re-derives the grid after every layout pass and drops the update when
	 * nothing changed (app/src/terminal/view.rs, after_terminal_view_layout). The
	 * DOM has no such per-layout signal, so hosts that relayout this surface say
	 * so here instead.
	 */
	refitToken?: number;
	focusToken?: number;
	visible?: boolean;
	features?: Partial<RendererFeatures>;
	marks?: readonly MarkRule[];
	onPaint?: () => void;
	onBlockFinished?: (event: BlockFinishedEvent) => void;
	onHint?: (hint: HintEvent) => void;
	onDraftChange?: (draft: string) => void;
}

function predictKeystroke(renderer: DomBlockRenderer | null, event: KeyboardEvent): void {
	if (!renderer) return;
	const now = performance.now();
	renderer.noteSend(now);
	renderer.predictKey({ text: event.key, ctrlKey: event.ctrlKey, altKey: event.altKey, metaKey: event.metaKey, isComposing: event.isComposing }, now);
}

export function TerminalSurface({
	core,
	theme,
	font,
	className,
	altScreenSurface,
	altScreenActive,
	host,
	strings = defaultStrings,
	onSend,
	onSendRaw,
	onGeometry,
	onPaint,
	onBlockFinished,
	onHint,
	onDraftChange,
	refitToken,
	focusToken,
	visible,
	features,
	marks,
}: TerminalSurfaceProps): ReactElement {
	const hostRef = useRef<HTMLDivElement | null>(null);
	const surfaceRef = useRef<HTMLDivElement | null>(null);
	const editorHostRef = useRef<HTMLDivElement | null>(null);
	const rendererRef = useRef<DomBlockRenderer | null>(null);
	const editorRef = useRef<LineEditor | null>(null);
	const onPaintRef = useRef(onPaint);
	onPaintRef.current = onPaint;
	const onBlockFinishedRef = useRef(onBlockFinished);
	onBlockFinishedRef.current = onBlockFinished;
	const onHintRef = useRef(onHint);
	onHintRef.current = onHint;
	const onDraftChangeRef = useRef(onDraftChange);
	onDraftChangeRef.current = onDraftChange;
	const visibleRef = useRef(visible);
	visibleRef.current = visible;
	const findBarRef = useRef<FindBar | null>(null);
	const gridColumnsRef = useRef(0);
	const gridRowsRef = useRef(0);
	const compositionRef = useRef<CompositionTarget | null>(null);
	const hostCapsRef = useRef(host);
	hostCapsRef.current = host;
	const featuresRef = useRef(features);
	featuresRef.current = features;
	const marksRef = useRef(marks);
	marksRef.current = marks;
	const secretPatterns = host?.secretPatterns;
	const secretPatternsRef = useRef(secretPatterns);
	secretPatternsRef.current = secretPatterns;
	const resolveFirstPath = host?.resolveFirstPath;
	const resolveFirstPathRef = useRef(resolveFirstPath);
	resolveFirstPathRef.current = resolveFirstPath;
	const confirmPaste = host?.confirmPaste;
	const confirmPasteRef = useRef(confirmPaste);
	confirmPasteRef.current = confirmPaste;

	const applyLinkProviders = useCallback(() => {
		const renderer = rendererRef.current;
		if (!renderer) return;
		const resolve = resolveFirstPathRef.current;
		if (!resolve) {
			renderer.setLinkProviders(DEFAULT_LINK_PROVIDERS);
			return;
		}
		const cwdOf = (blockId: string) => decodeBlocks(core.snapshot()).find((block) => block.id === blockId)?.cwd ?? "";
		renderer.setLinkProviders([
			...DEFAULT_LINK_PROVIDERS,
			createPathProvider((candidates, cwd) => resolve(candidates, cwd), cwdOf),
		]);
	}, [core]);

	const predictiveThresholdMs = host?.predictiveEcho?.thresholdMs;
	const applyPredictiveEcho = useCallback(() => {
		rendererRef.current?.setPredictiveEcho(predictiveThresholdMs === undefined ? null : { thresholdMs: predictiveThresholdMs });
	}, [predictiveThresholdMs]);
	const applyPredictiveEchoRef = useRef(applyPredictiveEcho);
	applyPredictiveEchoRef.current = applyPredictiveEcho;

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const editorHost = editorHostRef.current;
		if (!blockHost || !editorHost) {
			return;
		}
		const renderer = new DomBlockRenderer();
		renderer.setVisible(visibleRef.current ?? null);
		renderer.mount(blockHost, core);
		renderer.setFeatures(featuresRef.current ?? {});
		renderer.setSecretPatterns(secretPatternsRef.current ?? []);
		renderer.setMarks(marksRef.current ?? []);
		renderer.setTheme(theme);
		renderer.setFont(font);
		const editor = new LineEditor();
		editor.mount(editorHost, core, {
			send: onSend,
			sendRaw: onSendRaw,
			beforePassthrough: (event) => predictKeystroke(renderer, event),
			compositionAnchor: (parent) => anchorFromElement(parent, blockHost.querySelector("[data-terminal-cursor-cell]")),
			onDraftChange: (draft) => onDraftChangeRef.current?.(draft),
		});
		editor.setTheme(theme);
		editor.setFont(font);
		editor.setStrings(strings);
		editor.setPasteConfirm(confirmPasteRef.current ?? null);
		const findBar = createFindBar({
			core,
			renderer,
			host: {
				scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
				scrollToRow: (row, align) => renderer.scrollToRow(row, align),
				invalidate: (range) => renderer.invalidate(range),
				afterRepaint: (listener) => renderer.onPaint(listener),
				highlightFind: (find) => renderer.setFindHighlights(find),
			},
			strings,
		});
		findBar.mount(blockHost);
		const onRerun = (event: Event) => {
			const blockId = (event as CustomEvent<{ blockId?: string }>).detail?.blockId;
			if (!blockId) return;
			const block = decodeBlocks(core.snapshot()).find((candidate) => candidate.id === blockId);
			if (!block) return;
			editor.setText(block.command);
			editor.focus();
		};
		blockHost.addEventListener(RERUN_EVENT, onRerun);
		const offPaint = renderer.onPaint(() => onPaintRef.current?.());
		const offFinished = renderer.onBlockFinished((event) => onBlockFinishedRef.current?.(event));
		rendererRef.current = renderer;
		editorRef.current = editor;
		findBarRef.current = findBar;
		editor.setVisible(visibleRef.current !== false);
		applyLinkProviders();
		applyPredictiveEchoRef.current();
		return () => {
			blockHost.removeEventListener(RERUN_EVENT, onRerun);
			offPaint();
			offFinished();
			findBar.dispose();
			editor.dispose();
			renderer.predictionsClear();
			renderer.dispose();
			editorRef.current = null;
			rendererRef.current = null;
			findBarRef.current = null;
		};
	}, [applyLinkProviders, core, onSend, onSendRaw]);

	useLayoutEffect(() => {
		rendererRef.current?.setTheme(theme);
		editorRef.current?.setTheme(theme);
	}, [theme]);

	useLayoutEffect(() => {
		rendererRef.current?.setFont(font);
		editorRef.current?.setFont(font);
	}, [font]);

	const featuresKey = JSON.stringify(features ?? {});
	useLayoutEffect(() => {
		rendererRef.current?.setFeatures(features ?? {});
		core.setGraphemeClusters(resolveFeatures(features).graphemes);
	}, [core, featuresKey]);

	useLayoutEffect(() => {
		applyLinkProviders();
	}, [applyLinkProviders, resolveFirstPath]);

	useLayoutEffect(() => {
		rendererRef.current?.setSecretPatterns(secretPatterns ?? []);
	}, [secretPatterns]);

	const marksKey = JSON.stringify(marks ?? []);
	useLayoutEffect(() => {
		rendererRef.current?.setMarks(marksRef.current ?? []);
	}, [marksKey]);

	useLayoutEffect(() => {
		applyPredictiveEcho();
	}, [applyPredictiveEcho]);

	useLayoutEffect(() => {
		editorRef.current?.setStrings(strings);
	}, [strings]);

	useLayoutEffect(() => {
		editorRef.current?.setPasteConfirm(confirmPaste ?? null);
	}, [confirmPaste]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const renderer = rendererRef.current;
		if (!blockHost || !renderer) {
			return;
		}
		// force skips the unchanged-geometry guard. Warp draws the same
		// distinction (SizeUpdate::is_refresh): a refresh must reach the model
		// even when the numbers match, because the reason to ask is that
		// something outside this measurement may have moved.
		const apply = (force = false) => {
			// A pane laid out at zero -- collapsed, or not laid out yet -- is
			// skipped rather than recorded, so the next observation still applies.
			if (blockHost.clientWidth <= 0 || blockHost.clientHeight <= 0) {
				return;
			}
			const { cellWidth, cellHeight } = renderer.measure();
			if (cellWidth <= 0 || cellHeight <= 0) {
				return;
			}
			// Rows are laid out inside the block's padding, so the grid gets the
			// space left after it -- not the host's full box.
			const inset = renderer.blockContentInset();
			const columns = Math.max(1, Math.floor((blockHost.clientWidth - inset.x) / cellWidth));
			const rows = Math.max(1, Math.floor((blockHost.clientHeight - inset.y) / cellHeight));
			const changed = columns !== gridColumnsRef.current || rows !== gridRowsRef.current;
			if (!force && !changed) {
				return;
			}
			gridColumnsRef.current = columns;
			gridRowsRef.current = rows;
			if (changed) renderer.selectionClear();
			core.resize(columns, rows);
			onGeometry?.(columns, rows);
		};
		apply(true);
		if (typeof ResizeObserver !== "function") {
			return;
		}
		const observer = new ResizeObserver(() => apply());
		observer.observe(blockHost);
		return () => observer.disconnect();
	}, [core, onGeometry, refitToken]);

	useLayoutEffect(() => {
		rendererRef.current?.setVisible(visible ?? null);
		editorRef.current?.setVisible(visible !== false);
	}, [visible]);

	const [altActive, setAltActive] = useState(false);
	useLayoutEffect(() => {
		const read = () => setAltActive(core.snapshot().altScreen !== null);
		read();
		return core.onChange(read);
	}, [core]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		if (!blockHost || !altActive) {
			return;
		}
		const appCursor = () => core.snapshot().applicationCursorKeys;
		let active = true;
		const composition = createCompositionTarget({
			parent: blockHost,
			onCommit: (text) => onSendRaw(text),
			anchor: (parent) => anchorFromElement(parent, parent.querySelector("[data-terminal-cursor]")),
		});
		const onKeyDown = (event: KeyboardEvent) => {
			if (composition.isComposing() || event.isComposing || event.keyCode === 229) {
				return;
			}
			if (isCopyChord(event, isMacPlatform())) {
				return;
			}
			const data = encodeKey(event, appCursor());
			if (data === null) {
				return;
			}
			event.preventDefault();
			rendererRef.current?.selectionClear();
			predictKeystroke(rendererRef.current, event);
			onSendRaw(data);
		};
		// The alt screen has no line editor to hold the line, so every paste
		// belongs to the child.
		const onPaste = (event: ClipboardEvent) => {
			event.preventDefault();
			const data = event.clipboardData;
			const plan = planPaste({
				text: data?.getData("text/plain") ?? "",
				hasImage: clipboardHasImage(data),
				owned: false,
				bracketedPaste: core.snapshot().bracketedPaste,
			});
			void deliverPaste(
				plan,
				(bytes) => {
					if (active) onSendRaw(bytes);
				},
				hostCapsRef.current?.confirmPaste,
			);
		};
		blockHost.addEventListener("keydown", onKeyDown);
		blockHost.addEventListener("paste", onPaste);
		compositionRef.current = composition;
		composition.focus();
		return () => {
			active = false;
			blockHost.removeEventListener("keydown", onKeyDown);
			blockHost.removeEventListener("paste", onPaste);
			compositionRef.current = null;
			composition.dispose();
		};
	}, [altActive, core, onSendRaw]);

	useSurfaceInput(
		{ hostRef, editorHostRef, surfaceRef, rendererRef, compositionRef, gridColumnsRef, gridRowsRef, hostCapsRef, onHintRef },
		core,
		onSendRaw,
	);

	useLayoutEffect(() => {
		const findBar = findBarRef.current;
		if (!findBar) return;
		const onKeyDown = (event: KeyboardEvent) => {
			if ((event.metaKey || event.ctrlKey) && (event.key === "f" || event.key === "F")) {
				event.preventDefault();
				findBar.open();
			}
		};
		document.addEventListener("keydown", onKeyDown);
		return () => document.removeEventListener("keydown", onKeyDown);
	}, []);

	// Clicking the transcript belongs to the editor, the way clicking anywhere in
	// a terminal keeps you typing at the prompt. Without this the click lands on
	// the host (or nowhere) and the next keystroke goes nowhere. Runs on click,
	// not mousedown, so a drag-select is left alone.
	const altActiveRef = useRef(altActive);
	altActiveRef.current = altActive;
	const focusInput = useCallback(() => {
		if (altActiveRef.current) {
			compositionRef.current?.focus();
			return;
		}
		editorRef.current?.focus();
	}, []);

	useLayoutEffect(() => {
		if (focusToken === undefined) return;
		focusInput();
	}, [focusInput, focusToken]);

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const blockList = (
		<div className="terminal-surface" ref={surfaceRef}>
			{/* tabindex only while the alt-screen handler below is bound. In the
			    normal buffer the editor is the input surface, and a focusable host
			    steals the click: nothing handles keys there, so typing is dropped,
			    arrows scroll the list, and the first keypress paints a focus ring
			    around the whole terminal. */}
			<div
				ref={hostRef}
				className={hostClassName}
				onClick={focusInput}
				tabIndex={altActive ? 0 : undefined}
			/>
			<div ref={editorHostRef} className="terminal-editor-host" hidden={altActive} />
		</div>
	);
	return (
		<AltScreenSlot
			active={altScreenActive}
			surface={altScreenSurface}
			blockList={blockList}
		/>
	);
}
