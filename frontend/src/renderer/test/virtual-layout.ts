import { vi } from "vitest";

export const VIRTUAL_VIEWPORT_HEIGHT = 600;

export type VirtualLayoutOptions = {
	heights: () => readonly number[];
	viewportHeight?: number;
};

function indexOf(element: HTMLElement): number | undefined {
	const raw = element.getAttribute("data-index");
	if (raw === null) return undefined;
	const index = Number(raw);
	return Number.isFinite(index) ? index : undefined;
}

export function installVirtualLayout(options: VirtualLayoutOptions): () => void {
	const viewportHeight = options.viewportHeight ?? VIRTUAL_VIEWPORT_HEIGHT;
	const heightAt = (index: number) => options.heights()[index] ?? 0;

	const sizeOf = function (this: HTMLElement) {
		const index = indexOf(this);
		return index === undefined ? viewportHeight : heightAt(index);
	};

	vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
		const height = sizeOf.call(this);
		return {
			top: 0,
			bottom: height,
			left: 0,
			right: 800,
			width: 800,
			height,
			x: 0,
			y: 0,
			toJSON() {
				return this;
			},
		} as DOMRect;
	});
	vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockImplementation(sizeOf);
	vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(sizeOf);
	vi.spyOn(Element.prototype, "scrollHeight", "get").mockImplementation(function (this: Element) {
		if (!this.hasAttribute("data-block-scroll")) return sizeOf.call(this as HTMLElement);
		const sizer = this.querySelector<HTMLElement>("[data-block-sizer]");
		const styled = sizer === null ? Number.NaN : Number.parseFloat(sizer.style.height);
		return Number.isFinite(styled) ? styled : 0;
	});

	const proto = Element.prototype as unknown as Record<string, unknown>;
	const hadScrollTo = "scrollTo" in proto;
	proto.scrollTo = function (this: Element, arg: unknown) {
		if (typeof arg !== "object" || arg === null || !("top" in arg)) return;
		const top = (arg as { top?: number }).top;
		if (typeof top !== "number") return;
		const next = Math.max(0, top);
		if (this.scrollTop === next) return;
		this.scrollTop = next;
		const target = this;
		queueMicrotask(() => target.dispatchEvent(new Event("scroll")));
	};

	return () => {
		vi.restoreAllMocks();
		if (!hadScrollTo) delete proto.scrollTo;
	};
}
