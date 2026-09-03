import { useCallback, useLayoutEffect, useRef, useState, type ReactElement, type ReactNode } from "react";
import { clipboardHasImage, encodeKey, LineEditor, planPaste } from "@operator/terminal-editor";
import { createFindBar, DomBlockRenderer, RERUN_EVENT, type FindBar } from "@operator/terminal-renderer-dom";
import {
	createCompositionTarget,
	decodeBlocks,
	defaultStrings,
	type CompositionTarget,
	type FontConfig,
	type HostCapabilities,
	type TerminalCore,
	type TerminalSnapshot,
	type TerminalStrings,
	type TerminalTheme,
} from "@operator/terminal-core";
import { AltScreenSlot } from "./AltScreenSlot.js";
import { encodeMouseReport, type MouseReportKind } from "./mouse-report.js";

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
	onPaint?: () => void;
}

// macOS hands a native app an already-accelerated scroll delta: a flick reports
// tens of pixels per event and keeps reporting through a momentum tail. The
// WebView hands us the raw gesture instead -- measured on a trackpad, ~1-3px per
// event at ~115 events/sec, with no tail -- so a flick and a crawl travel nearly
// the same distance and the alt screen advances a row at a time. Scale the delta
// by gesture velocity to restore the curve the platform withheld. Below the
// reference speed the gain is 1, so slow, deliberate scrolling stays exact.
const ACCEL_REFERENCE_PX_PER_SEC = 100;
const ACCEL_MAX_GAIN = 6;
// A gap this long means fingers left the trackpad; the next event starts a new
// gesture rather than inheriting the old one's speed.
const GESTURE_IDLE_MS = 200;
// Velocity is averaged over recent events: a single jittery sample should not
// launch the viewport. Averaging up from zero also means a gesture has to
// sustain speed before it accelerates, so a short nudge stays a short nudge.
const VELOCITY_SMOOTHING = 0.3;
// Events closer together than this are one frame's worth of coalesced motion,
// not evidence of speed; dividing by their sub-millisecond gap would report
// thousands of pixels per second for an ordinary scroll.
const MIN_VELOCITY_SAMPLE_MS = 4;

function accelerationGain(velocityPxPerSec: number): number {
	const gain = velocityPxPerSec / ACCEL_REFERENCE_PX_PER_SEC;
	return Math.min(Math.max(gain, 1), ACCEL_MAX_GAIN);
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
}: TerminalSurfaceProps): ReactElement {
	const hostRef = useRef<HTMLDivElement | null>(null);
	const editorHostRef = useRef<HTMLDivElement | null>(null);
	const rendererRef = useRef<DomBlockRenderer | null>(null);
	const editorRef = useRef<LineEditor | null>(null);
	const onPaintRef = useRef(onPaint);
	onPaintRef.current = onPaint;
	const findBarRef = useRef<FindBar | null>(null);
	const gridColumnsRef = useRef(0);
	const gridRowsRef = useRef(0);
	const compositionRef = useRef<CompositionTarget | null>(null);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const editorHost = editorHostRef.current;
		if (!blockHost || !editorHost) {
			return;
		}
		const renderer = new DomBlockRenderer();
		renderer.mount(blockHost, core);
		renderer.setTheme(theme);
		renderer.setFont(font);
		renderer.setHostCapabilities(host ?? null);
		const editor = new LineEditor();
		editor.mount(editorHost, core, { send: onSend, sendRaw: onSendRaw });
		editor.setTheme(theme);
		editor.setFont(font);
		editor.setStrings(strings);
		const findBar = createFindBar({
			core,
			renderer,
			host: {
				scrollToBlock: (id, align) => renderer.scrollToBlock(id, align),
				invalidate: (range) => renderer.invalidate(range),
				afterRepaint: (listener) => renderer.onPaint(listener),
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
		rendererRef.current = renderer;
		editorRef.current = editor;
		findBarRef.current = findBar;
		return () => {
			blockHost.removeEventListener(RERUN_EVENT, onRerun);
			offPaint();
			findBar.dispose();
			editor.dispose();
			renderer.dispose();
			editorRef.current = null;
			rendererRef.current = null;
			findBarRef.current = null;
		};
	}, [core, onSend, onSendRaw]);

	useLayoutEffect(() => {
		rendererRef.current?.setTheme(theme);
		editorRef.current?.setTheme(theme);
	}, [theme]);

	useLayoutEffect(() => {
		rendererRef.current?.setFont(font);
		editorRef.current?.setFont(font);
	}, [font]);

	useLayoutEffect(() => {
		rendererRef.current?.setHostCapabilities(host ?? null);
	}, [host]);

	useLayoutEffect(() => {
		editorRef.current?.setStrings(strings);
	}, [strings]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const renderer = rendererRef.current;
		if (!blockHost || !renderer) {
			return;
		}
		let lastColumns = 0;
		let lastRows = 0;
		const apply = () => {
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
			gridColumnsRef.current = columns;
			gridRowsRef.current = rows;
			if (columns === lastColumns && rows === lastRows) {
				return;
			}
			lastColumns = columns;
			lastRows = rows;
			core.resize(columns, rows);
			onGeometry?.(columns, rows);
		};
		apply();
		if (typeof ResizeObserver !== "function") {
			return;
		}
		const observer = new ResizeObserver(apply);
		observer.observe(blockHost);
		return () => observer.disconnect();
	}, [core, onGeometry]);

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
		const composition = createCompositionTarget({
			parent: blockHost,
			onCommit: (text) => onSendRaw(text),
		});
		const onKeyDown = (event: KeyboardEvent) => {
			if (composition.isComposing() || event.isComposing || event.keyCode === 229) {
				return;
			}
			const data = encodeKey(event, appCursor());
			if (data === null) {
				return;
			}
			event.preventDefault();
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
			if (plan.kind === "send") onSendRaw(plan.data);
		};
		blockHost.addEventListener("keydown", onKeyDown);
		blockHost.addEventListener("paste", onPaste);
		compositionRef.current = composition;
		composition.focus();
		return () => {
			blockHost.removeEventListener("keydown", onKeyDown);
			blockHost.removeEventListener("paste", onPaste);
			compositionRef.current = null;
			composition.dispose();
		};
	}, [altActive, core, onSendRaw]);

	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		if (!blockHost) return;
		let pendingWheelLines = 0;
		let velocityPxPerSec = 0;
		let lastWheelAt = 0;
		let dragButton: 0 | 1 | 2 | null = null;
		const sampleVelocity = (deltaY: number): number => {
			const now = performance.now();
			const elapsed = now - lastWheelAt;
			if (elapsed > GESTURE_IDLE_MS) {
				lastWheelAt = now;
				velocityPxPerSec = 0;
				return 0;
			}
			if (elapsed < MIN_VELOCITY_SAMPLE_MS) {
				return velocityPxPerSec;
			}
			lastWheelAt = now;
			const sample = (Math.abs(deltaY) / elapsed) * 1000;
			velocityPxPerSec += (sample - velocityPxPerSec) * VELOCITY_SMOOTHING;
			return velocityPxPerSec;
		};
		const modifiersOf = (event: MouseEvent) => ({
			shift: event.shiftKey,
			alt: event.altKey,
			ctrl: event.ctrlKey,
		});
		const buttonOf = (event: MouseEvent): 0 | 1 | 2 | null =>
			event.button === 0 ? 0 : event.button === 1 ? 1 : event.button === 2 ? 2 : null;
		const reportFor = (kind: MouseReportKind, button: 0 | 1 | 2, event: MouseEvent) => {
			const snapshot = core.snapshot();
			if (event.shiftKey || !snapshot.sgrMouse) return null;
			const { column, row } = pointerCell(blockHost, event, rendererRef.current, snapshot, {
				columns: gridColumnsRef.current,
				rows: gridRowsRef.current,
			});
			return encodeMouseReport({
				kind,
				button,
				column,
				row,
				sgrMouse: snapshot.sgrMouse,
				trackingLevel: snapshot.mouseTrackingLevel,
				modifiers: modifiersOf(event),
				altScreen: snapshot.altScreen !== null,
			});
		};
		const onMouseDown = (event: MouseEvent) => {
			compositionRef.current?.focus();
			const button = buttonOf(event);
			if (button === null) return;
			const data = reportFor("press", button, event);
			if (data === null) return;
			event.preventDefault();
			dragButton = button;
			onSendRaw(data);
		};
		const onMouseMove = (event: MouseEvent) => {
			const data =
				dragButton === null ? reportFor("move", 0, event) : reportFor("drag", dragButton, event);
			if (data === null) return;
			onSendRaw(data);
		};
		const onMouseUp = (event: MouseEvent) => {
			const button = buttonOf(event);
			if (button === null) return;
			const target = event.target;
			const inside = target instanceof Node && blockHost.contains(target);
			if (dragButton === null && !inside) return;
			dragButton = null;
			const data = reportFor("release", button, event);
			if (data === null) return;
			if (inside) event.preventDefault();
			onSendRaw(data);
		};
		const onWheel = (event: WheelEvent) => {
			const snapshot = core.snapshot();
			const altScreen = snapshot.altScreen !== null;
			const reports = !event.shiftKey && snapshot.sgrMouse && snapshot.mouseTrackingLevel !== 0;
			if (!reports && !altScreen) return;
			event.preventDefault();
			const measuredCellHeight = rendererRef.current?.measure().cellHeight ?? 0;
			const deltaLines =
				event.deltaMode === WheelEvent.DOM_DELTA_LINE
					? event.deltaY
					: event.deltaMode === WheelEvent.DOM_DELTA_PAGE
						? event.deltaY * (snapshot.altScreen?.rows ?? 1)
						: measuredCellHeight > 0
							? (event.deltaY * accelerationGain(sampleVelocity(event.deltaY))) / measuredCellHeight
							: 0;
			if (!Number.isFinite(deltaLines)) return;
			pendingWheelLines += deltaLines;
			const lines = Math.trunc(pendingWheelLines);
			pendingWheelLines -= lines;
			if (lines === 0) return;
			const count = Math.abs(lines);
			if (reports) {
				const { column, row } = pointerCell(blockHost, event, rendererRef.current, snapshot, {
					columns: gridColumnsRef.current,
					rows: gridRowsRef.current,
				});
				const data = encodeMouseReport({
					kind: lines > 0 ? "wheelDown" : "wheelUp",
					button: 0,
					column,
					row,
					sgrMouse: snapshot.sgrMouse,
					trackingLevel: snapshot.mouseTrackingLevel,
					modifiers: { shift: event.shiftKey, alt: event.altKey, ctrl: event.ctrlKey },
					altScreen,
				});
				if (data !== null) onSendRaw(data.repeat(count));
				return;
			}
			const prefix = snapshot.applicationCursorKeys ? "\x1bO" : "\x1b[";
			onSendRaw(`${prefix}${lines > 0 ? "B" : "A"}`.repeat(count));
		};
		const staysInside = (event: FocusEvent) => {
			const related = event.relatedTarget;
			return related instanceof Node && blockHost.contains(related);
		};
		const onFocusIn = (event: FocusEvent) => {
			if (staysInside(event)) return;
			if (!core.snapshot().focusReporting) return;
			onSendRaw("\x1b[I");
		};
		const onFocusOut = (event: FocusEvent) => {
			if (staysInside(event)) return;
			if (!core.snapshot().focusReporting) return;
			onSendRaw("\x1b[O");
		};
		blockHost.addEventListener("mousedown", onMouseDown);
		blockHost.addEventListener("mousemove", onMouseMove);
		window.addEventListener("mouseup", onMouseUp);
		blockHost.addEventListener("wheel", onWheel, { passive: false });
		blockHost.addEventListener("focusin", onFocusIn);
		blockHost.addEventListener("focusout", onFocusOut);
		return () => {
			blockHost.removeEventListener("mousedown", onMouseDown);
			blockHost.removeEventListener("mousemove", onMouseMove);
			window.removeEventListener("mouseup", onMouseUp);
			blockHost.removeEventListener("wheel", onWheel);
			blockHost.removeEventListener("focusin", onFocusIn);
			blockHost.removeEventListener("focusout", onFocusOut);
		};
	}, [core, onSendRaw]);

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
	const focusEditorFromHost = useCallback(() => {
		const selection = document.getSelection();
		if (selection && !selection.isCollapsed) return;
		if (altActive) {
			compositionRef.current?.focus();
			return;
		}
		editorRef.current?.focus();
	}, [altActive]);

	const hostClassName = className ? `terminal-host ${className}` : "terminal-host";
	const blockList = (
		<div className="terminal-surface">
			{/* tabindex only while the alt-screen handler below is bound. In the
			    normal buffer the editor is the input surface, and a focusable host
			    steals the click: nothing handles keys there, so typing is dropped,
			    arrows scroll the list, and the first keypress paints a focus ring
			    around the whole terminal. */}
			<div
				ref={hostRef}
				className={hostClassName}
				onClick={focusEditorFromHost}
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

function pointerCell(
	host: HTMLElement,
	event: MouseEvent | WheelEvent,
	renderer: DomBlockRenderer | null,
	snapshot: TerminalSnapshot,
	grid: { columns: number; rows: number },
): { column: number; row: number } {
	if (!renderer) {
		return { column: 1, row: 1 };
	}
	const metrics = renderer.measure();
	if (metrics.cellWidth <= 0 || metrics.cellHeight <= 0) {
		return { column: 1, row: 1 };
	}
	const bounds = host.getBoundingClientRect();
	const painted =
		snapshot.altScreen === null
			? renderer.rowOrigin(firstScreenRow(snapshot, grid.rows))
			: null;
	const left = painted?.left ?? bounds.left;
	const top = painted?.top ?? bounds.top;
	const column = Math.floor((event.clientX - left) / metrics.cellWidth) + 1;
	const row = Math.floor((event.clientY - top) / metrics.cellHeight) + 1;
	const columnLimit = snapshot.altScreen?.columns ?? grid.columns;
	const rowLimit = snapshot.altScreen?.rows ?? grid.rows;
	return {
		column: clampCell(column, columnLimit),
		row: clampCell(row, rowLimit),
	};
}

function clampCell(value: number, limit: number): number {
	if (limit > 0) return Math.min(Math.max(1, value), limit);
	return Math.max(1, value);
}

function firstScreenRow(snapshot: TerminalSnapshot, rows: number): number {
	if (rows <= 0) return 0;
	return Math.max(0, snapshot.rows.length / 2 - rows);
}
