import { useLayoutEffect, type RefObject } from "react";
import type { CompositionTarget, HostCapabilities, TerminalCore } from "@operator/terminal-core";
import type { DetectedLink, DomBlockRenderer, HintEvent, SelectionKind, SelectionPoint } from "@operator/terminal-renderer-dom";
import { autoScrollRows, exceedsDragThreshold, isCopyChord, isHintChord, kindForClickCount, linkModifierHeld } from "./selection-gesture.js";
import {
	accelerationGain,
	GESTURE_IDLE_MS,
	isMacPlatform,
	MIN_VELOCITY_SAMPLE_MS,
	pointerCell,
	SELECTION_CHROME,
	VELOCITY_SMOOTHING,
} from "./surface-geometry.js";
import { encodeMouseReport, type MouseReportKind } from "./mouse-report.js";

export type SurfaceInputRefs = Readonly<{
	hostRef: RefObject<HTMLDivElement | null>;
	editorHostRef: RefObject<HTMLDivElement | null>;
	surfaceRef: RefObject<HTMLDivElement | null>;
	rendererRef: RefObject<DomBlockRenderer | null>;
	compositionRef: RefObject<CompositionTarget | null>;
	gridColumnsRef: RefObject<number>;
	gridRowsRef: RefObject<number>;
	hostCapsRef: RefObject<HostCapabilities | undefined>;
	onHintRef: RefObject<((hint: HintEvent) => void) | undefined>;
}>;

export function useSurfaceInput(refs: SurfaceInputRefs, core: TerminalCore, onSendRaw: (data: string) => void): void {
	const { hostRef, editorHostRef, surfaceRef, rendererRef, compositionRef, gridColumnsRef, gridRowsRef, hostCapsRef, onHintRef } = refs;
	useLayoutEffect(() => {
		const blockHost = hostRef.current;
		const editorHost = editorHostRef.current;
		if (!blockHost || !editorHost) return;
		let pendingWheelLines = 0;
		let velocityPxPerSec = 0;
		let lastWheelAt = 0;
		let dragButton: 0 | 1 | 2 | null = null;
		let pressOrigin: { x: number; y: number } | null = null;
		let pressPoint: SelectionPoint | null = null;
		let pressKind: SelectionKind = "simple";
		let dragging = false;
		let autoScroll: number | null = null;
		let lastPointer = { x: 0, y: 0 };
		const renderer = () => rendererRef.current;
		const stopAutoScroll = () => {
			if (autoScroll !== null) cancelAnimationFrame(autoScroll);
			autoScroll = null;
		};
		const extendTo = (x: number, y: number) => {
			const target = renderer();
			if (!target) return;
			const bounds = blockHost.getBoundingClientRect();
			const clampedX = bounds.width > 0 ? Math.min(Math.max(x, bounds.left), bounds.right) : x;
			const clampedY = bounds.height > 0 ? Math.min(Math.max(y, bounds.top), bounds.bottom) : y;
			const point = target.pointAt(clampedX, clampedY);
			if (point) target.selectionUpdate(point);
		};
		const autoScrollStep = () => {
			autoScroll = null;
			const bounds = blockHost.getBoundingClientRect();
			const rows = autoScrollRows(lastPointer.y, bounds.top, bounds.bottom);
			if (rows === 0 || !dragging) return;
			const cellHeight = renderer()?.measure().cellHeight ?? 0;
			blockHost.scrollTop += rows * cellHeight;
			extendTo(lastPointer.x, lastPointer.y);
			autoScroll = requestAnimationFrame(autoScrollStep);
		};
		const onWindowMouseMove = (event: MouseEvent) => {
			if (!pressOrigin || !pressPoint) return;
			lastPointer = { x: event.clientX, y: event.clientY };
			const target = renderer();
			if (!target) return;
			if (!dragging) {
				if (!exceedsDragThreshold(pressOrigin, event.clientX, event.clientY)) return;
				dragging = true;
				if (pressKind === "simple") target.selectionBegin(pressPoint, "simple");
			}
			extendTo(event.clientX, event.clientY);
			const bounds = blockHost.getBoundingClientRect();
			if (autoScrollRows(event.clientY, bounds.top, bounds.bottom) !== 0) {
				if (autoScroll === null && core.snapshot().altScreen === null) autoScroll = requestAnimationFrame(autoScrollStep);
			} else {
				stopAutoScroll();
			}
		};
		const onWindowMouseUp = () => {
			const target = renderer();
			if (target && pressOrigin && !dragging && pressKind === "simple") target.selectionClear();
			pressOrigin = null;
			pressPoint = null;
			dragging = false;
			stopAutoScroll();
			window.removeEventListener("mousemove", onWindowMouseMove);
			window.removeEventListener("mouseup", onWindowMouseUp);
		};
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
		const activateLink = (link: DetectedLink) => {
			const caps = hostCapsRef.current;
			if (!caps) return;
			if (link.kind === "path") {
				if (link.path !== undefined) void caps.openPath?.(link.path, link.line, link.column);
				return;
			}
			if (link.uri !== undefined) void caps.openLink(link.uri);
		};
		const onHoverMove = (event: MouseEvent) => {
			if (pressOrigin) return;
			renderer()?.hoverAt(event.clientX, event.clientY);
		};
		const onHoverLeave = () => renderer()?.clearHover();
		const onMouseDown = (event: MouseEvent) => {
			compositionRef.current?.focus();
			const button = buttonOf(event);
			if (button === null) return;
			if (button === 0 && linkModifierHeld(event, isMacPlatform())) {
				renderer()?.hoverAt(event.clientX, event.clientY);
				const link = renderer()?.hoveredLink();
				if (link) {
					event.preventDefault();
					activateLink(link);
					return;
				}
			}
			if (button === 0 && !event.altKey) renderer()?.revealSecretAt(event.clientX, event.clientY);
			const data = reportFor("press", button, event);
			if (data !== null) {
				event.preventDefault();
				dragButton = button;
				onSendRaw(data);
				return;
			}
			if (button !== 0) return;
			if (event.target instanceof Element && event.target.closest(SELECTION_CHROME)) return;
			const target = renderer();
			if (!target) return;
			const point = target.pointAt(event.clientX, event.clientY);
			if (!point) return;
			event.preventDefault();
			pressOrigin = { x: event.clientX, y: event.clientY };
			pressPoint = point;
			pressKind = kindForClickCount(event.detail);
			dragging = false;
			if (pressKind !== "simple") target.selectionBegin(point, pressKind);
			window.addEventListener("mousemove", onWindowMouseMove);
			window.addEventListener("mouseup", onWindowMouseUp);
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
		const onCopyKey = (event: KeyboardEvent) => {
			const target = renderer();
			if (!target || !isCopyChord(event, isMacPlatform())) return;
			const text = target.selectedText();
			if (text === null) return;
			event.preventDefault();
			event.stopPropagation();
			void hostCapsRef.current?.writeClipboard(text);
		};
		const onHintKey = (event: KeyboardEvent) => {
			const target = renderer();
			if (!target) return;
			if (!target.hintActive()) {
				if (!isHintChord(event)) return;
				event.preventDefault();
				event.stopPropagation();
				target.hintBegin();
				return;
			}
			event.preventDefault();
			event.stopPropagation();
			if (event.key === "Escape") {
				target.hintCancel();
				return;
			}
			if (event.key === "Backspace") {
				target.hintBackspace();
				return;
			}
			if (event.key.length !== 1 || event.metaKey || event.ctrlKey || event.altKey) {
				target.hintCancel();
				return;
			}
			const hint = target.hintType(event.key);
			if (hint) onHintRef.current?.(hint);
		};
		const onEditorTyping = (event: KeyboardEvent) => {
			if (event.key === "Shift" || event.key === "Control" || event.key === "Alt" || event.key === "Meta") return;
			if (isCopyChord(event, isMacPlatform())) return;
			renderer()?.selectionClear();
		};
		const surface = surfaceRef.current;
		const reportFocus = () => rendererRef.current?.setFocused(surface !== null && surface.contains(document.activeElement));
		const onSurfaceFocusIn = () => reportFocus();
		const onSurfaceFocusOut = () => reportFocus();
		blockHost.addEventListener("mousedown", onMouseDown);
		blockHost.addEventListener("mousemove", onMouseMove);
		blockHost.addEventListener("mousemove", onHoverMove);
		blockHost.addEventListener("mouseleave", onHoverLeave);
		window.addEventListener("mouseup", onMouseUp);
		blockHost.addEventListener("wheel", onWheel, { passive: false });
		blockHost.addEventListener("focusin", onFocusIn);
		blockHost.addEventListener("focusout", onFocusOut);
		blockHost.addEventListener("keydown", onCopyKey);
		editorHost.addEventListener("keydown", onCopyKey);
		editorHost.addEventListener("keydown", onEditorTyping);
		surface?.addEventListener("focusin", onSurfaceFocusIn);
		surface?.addEventListener("focusout", onSurfaceFocusOut);
		surface?.addEventListener("keydown", onHintKey, true);
		return () => {
			blockHost.removeEventListener("mousedown", onMouseDown);
			blockHost.removeEventListener("mousemove", onMouseMove);
			blockHost.removeEventListener("mousemove", onHoverMove);
			blockHost.removeEventListener("mouseleave", onHoverLeave);
			window.removeEventListener("mouseup", onMouseUp);
			blockHost.removeEventListener("wheel", onWheel);
			blockHost.removeEventListener("focusin", onFocusIn);
			blockHost.removeEventListener("focusout", onFocusOut);
			blockHost.removeEventListener("keydown", onCopyKey);
			editorHost.removeEventListener("keydown", onCopyKey);
			editorHost.removeEventListener("keydown", onEditorTyping);
			surface?.removeEventListener("focusin", onSurfaceFocusIn);
			surface?.removeEventListener("focusout", onSurfaceFocusOut);
			surface?.removeEventListener("keydown", onHintKey, true);
			window.removeEventListener("mousemove", onWindowMouseMove);
			window.removeEventListener("mouseup", onWindowMouseUp);
			stopAutoScroll();
		};
	}, [core, onSendRaw]);
}
