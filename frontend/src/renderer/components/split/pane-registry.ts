import type { PaneGeometry, Rect } from "../../lib/split-drop";

const elements = new Map<string, { pane: HTMLElement | null; strip: HTMLElement | null }>();

export function registerPaneElement(paneId: string, part: "pane" | "strip", element: HTMLElement | null): void {
	const entry = elements.get(paneId) ?? { pane: null, strip: null };
	entry[part] = element;
	if (!entry.pane && !entry.strip) elements.delete(paneId);
	else elements.set(paneId, entry);
}

function toRect(rect: DOMRect): Rect {
	return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
}

export function readPaneGeometry(paneIds: string[]): PaneGeometry[] {
	return paneIds.flatMap((paneId) => {
		const entry = elements.get(paneId);
		if (!entry?.pane || !entry.strip) return [];
		const tabs = [...entry.strip.querySelectorAll<HTMLElement>("[data-split-tab]")].map((tab) =>
			toRect(tab.getBoundingClientRect()),
		);
		return [{ paneId, pane: toRect(entry.pane.getBoundingClientRect()), strip: toRect(entry.strip.getBoundingClientRect()), tabs }];
	});
}
