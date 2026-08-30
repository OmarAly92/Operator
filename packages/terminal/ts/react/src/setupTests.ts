import "@testing-library/jest-dom/vitest";

if (typeof globalThis.ResizeObserver !== "function") {
	class ResizeObserverPolyfill {
		private readonly callback: ResizeObserverCallback;
		private readonly targets: Set<Element>;

		constructor(callback: ResizeObserverCallback) {
			this.callback = callback;
			this.targets = new Set();
		}

		observe(target: Element): void {
			this.targets.add(target);
			target.addEventListener("resize", this.handleResize);
		}

		unobserve(target: Element): void {
			this.targets.delete(target);
			target.removeEventListener("resize", this.handleResize);
		}

		disconnect(): void {
			for (const target of this.targets) {
				target.removeEventListener("resize", this.handleResize);
			}
			this.targets.clear();
		}

		private readonly handleResize = (): void => {
			const entries: ResizeObserverEntry[] = [];
			for (const target of this.targets) {
				entries.push({
					target,
					contentRect: target.getBoundingClientRect(),
					borderBoxSize: [{ inlineSize: 0, blockSize: 0 }],
					contentBoxSize: [{ inlineSize: 0, blockSize: 0 }],
					devicePixelContentBoxSize: [{ inlineSize: 0, blockSize: 0 }],
				});
			}
			this.callback(entries, this);
		};
	}

	globalThis.ResizeObserver = ResizeObserverPolyfill as unknown as typeof ResizeObserver;
}
