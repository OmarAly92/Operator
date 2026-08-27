import { useVirtualizer } from "@tanstack/react-virtual";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useRef, useState } from "react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { installVirtualLayout, VIRTUAL_VIEWPORT_HEIGHT } from "./virtual-layout";

const heightOf = (label: string) => 60 + (Number(label.replace(/\D/g, "")) % 5) * 40;
let currentItems: string[] = [];

function List({ items }: { items: string[] }) {
	const ref = useRef<HTMLDivElement | null>(null);
	const pinned = useRef(true);
	const virtualizer = useVirtualizer({
		count: items.length,
		getScrollElement: () => ref.current,
		estimateSize: () => 96,
		getItemKey: (index) => items[index],
		anchorTo: "end",
		followOnAppend: true,
		overscan: 4,
	});
	return (
		<div
			data-block-scroll
			data-testid="scroll"
			onScroll={(event) => {
				const node = event.currentTarget;
				pinned.current = node.scrollTop >= virtualizer.getTotalSize() - node.clientHeight - 24;
			}}
			ref={ref}
			style={{ overflowY: "auto" }}
		>
			<div data-block-sizer style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
				{virtualizer.getVirtualItems().map((row) => (
					<div
						data-index={row.index}
						data-start={row.start}
						data-testid="row"
						key={row.key}
						ref={virtualizer.measureElement}
					>
						{items[row.index]}
					</div>
				))}
			</div>
		</div>
	);
}

function Harness() {
	const [items, setItems] = useState(() => Array.from({ length: 300 }, (_, index) => `b-${index}`));
	currentItems = items;
	return (
		<>
			<button
				onClick={() => setItems((prev) => [...Array.from({ length: 40 }, (_, i) => `old-${i}`), ...prev])}
				type="button"
			>
				prepend
			</button>
			<button onClick={() => setItems((prev) => [...prev, `new-${prev.length}`])} type="button">
				append
			</button>
			<List items={items} />
		</>
	);
}

describe("installVirtualLayout", () => {
	let teardown: () => void;
	beforeEach(() => {
		teardown = installVirtualLayout({ heights: () => currentItems.map(heightOf) });
	});
	afterEach(() => teardown());

	it("gives rows their real measured height", async () => {
		render(<Harness />);
		await act(async () => {});
		const row = screen.getAllByTestId("row")[0];
		expect(row.getBoundingClientRect().height).toBe(heightOf(row.textContent ?? ""));
	});

	it("reports the sizer height as the scroll height", async () => {
		render(<Harness />);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		const sizer = node.querySelector<HTMLElement>("[data-block-sizer]");
		expect(node.scrollHeight).toBe(Number.parseFloat(sizer?.style.height ?? "0"));
		expect(node.scrollHeight).toBeGreaterThan(VIRTUAL_VIEWPORT_HEIGHT);
	});

	it("makes a programmatic scroll move the element and notify the virtualizer", async () => {
		const onScroll = vi.fn();
		render(
			<div data-block-scroll data-testid="scroll" onScroll={onScroll} ref={(node) => {
				if (node !== null) node.scrollTo({ top: 250 });
			}} style={{ overflowY: "auto" }}>
				<div style={{ height: 5000 }} data-block-sizer />
			</div>,
		);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		expect(node.scrollTop).toBe(250);
		await waitFor(() => expect(onScroll).toHaveBeenCalled());
	});

	it("windows a long list", async () => {
		render(<Harness />);
		await act(async () => {});
		const rows = screen.getAllByTestId("row").length;
		expect(rows).toBeGreaterThan(0);
		expect(rows).toBeLessThan(30);
	});

	it("holds an anchored prepend to a zero delta", async () => {
		render(<Harness />);
		await act(async () => {});
		const node = screen.getByTestId("scroll");
		act(() => {
			node.scrollTop = 1000;
			fireEvent.scroll(node);
		});
		const anchor = screen.getAllByTestId("row").find((row) => {
			const start = Number(row.dataset.start);
			return start <= node.scrollTop && start + heightOf(row.textContent ?? "") > node.scrollTop;
		});
		expect(anchor).toBeDefined();
		const label = anchor?.textContent ?? "";
		const before = Number(anchor?.dataset.start) - node.scrollTop;
		act(() => screen.getByText("prepend").click());
		expect(Number(screen.getByText(label).dataset.start) - node.scrollTop).toBe(before);
	});

	it("restores Element.prototype.scrollTo on teardown", async () => {
		render(<Harness />);
		await act(async () => {});
		teardown();
		expect("scrollTo" in Element.prototype).toBe(false);
		teardown = installVirtualLayout({ heights: () => currentItems.map(heightOf) });
		await waitFor(() => expect("scrollTo" in Element.prototype).toBe(true));
	});
});
