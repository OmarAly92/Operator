import { useLayoutEffect, type RefObject } from "react";
import type { TerminalCore } from "@operator/terminal-core";

export const POINTER_SHAPE_PROPERTY = "--terminal-pointer-shape";

export function useProgramMessages(
	core: TerminalCore,
	surfaceRef: RefObject<HTMLElement | null>,
	onTitleRef: RefObject<((title: string) => void) | undefined>,
): void {
	useLayoutEffect(() => {
		const surface = surfaceRef.current;
		const apply = (shape: string) => {
			if (!surface) return;
			if (shape) surface.style.setProperty(POINTER_SHAPE_PROPERTY, shape);
			else surface.style.removeProperty(POINTER_SHAPE_PROPERTY);
		};
		apply(core.pointerShape());
		const off = core.onProgramMessage((event) => {
			if (event.kind === "pointer") apply(event.shape);
			else if (event.kind === "title") onTitleRef.current?.(event.title);
		});
		return () => {
			off();
			surface?.style.removeProperty(POINTER_SHAPE_PROPERTY);
		};
	}, [core, surfaceRef, onTitleRef]);
}
