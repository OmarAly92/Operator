import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import { installVirtualLayout } from "../../test/virtual-layout";
import { BlockList } from "./BlockList";

function block(seq: number, lines = 1): SessionBlock {
	return {
		id: `seq-${seq}`,
		firstSeq: seq,
		lastSeq: seq,
		kind: "tool",
		status: "ok",
		title: `Bash ${seq}`,
		body: Array.from({ length: lines }, (_, line) => `line ${line} of block ${seq}`).join("\n"),
		truncatedLines: 0,
		redacted: false,
	};
}

function range(from: number, to: number, lines?: (seq: number) => number): SessionBlock[] {
	const out: SessionBlock[] = [];
	for (let seq = from; seq <= to; seq += 1) out.push(block(seq, lines?.(seq) ?? 1));
	return out;
}

const heightOfBlock = (item: SessionBlock) => 40 + item.body.split("\n").length * 20;

let current: SessionBlock[] = [];

function Harness({ initial, sessionId = "s-1" }: { initial: SessionBlock[]; sessionId?: string }) {
	const [blocks, setBlocks] = useState(initial);
	const [session, setSession] = useState(sessionId);
	current = blocks;
	return (
		<>
			<button onClick={() => setBlocks((prev) => [...range(1, 40), ...prev])} type="button">prepend</button>
			<button onClick={() => setBlocks((prev) => [...prev, block(9999, 2)])} type="button">append</button>
			<button
				onClick={() => {
					setSession("s-2");
					setBlocks(range(500, 505));
				}}
				type="button"
			>
				switch
			</button>
			<div style={{ height: 600 }}>
				<BlockList blocks={blocks} sessionId={session} />
			</div>
		</>
	);
}

async function mount(initial: SessionBlock[]) {
	current = initial;
	render(<Harness initial={initial} />);
	await act(async () => {});
}

describe("BlockList", () => {
	let teardown: () => void;
	beforeEach(() => {
		current = [];
		teardown = installVirtualLayout({ heights: () => current.map(heightOfBlock) });
	});
	afterEach(() => {
		teardown();
		cleanup();
	});

	it("renders one card per block for a short session", async () => {
		await mount(range(1, 3));

		expect(screen.getAllByTestId("session-block")).toHaveLength(3);
		expect(screen.getAllByText("Bash 1").length).toBeGreaterThan(0);
		expect(screen.getAllByText("Bash 3").length).toBeGreaterThan(0);
	});

	it("mounts a small window of a long session", async () => {
		await mount(range(1, 800, (seq) => 1 + (seq % 5)));

		const mounted = screen.getAllByTestId("session-block").length;
		expect(mounted).toBeGreaterThan(0);
		expect(mounted).toBeLessThan(30);
	});

	it("opens at the newest block", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		expect(screen.getByText("Bash 300")).toBeInTheDocument();
		expect(screen.queryByText("Bash 1")).not.toBeInTheDocument();
	});

	it("follows a block appended while pinned", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		await act(async () => screen.getByText("append").click());

		expect(screen.getByText("Bash 9999")).toBeInTheDocument();
	});

	it("does not follow a block appended while scrolled up", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 1000;
			fireEvent.scroll(node);
		});

		await act(async () => screen.getByText("append").click());

		expect(screen.queryByText("Bash 9999")).not.toBeInTheDocument();
		expect(node.scrollTop).toBe(1000);
	});

	it("does not move the block being read when older blocks arrive", async () => {
		await mount(range(100, 400, (seq) => 1 + (seq % 5)));
		const node = screen.getByRole("log");
		await act(async () => {
			node.scrollTop = 2000;
			fireEvent.scroll(node);
		});
		const rows = [...document.querySelectorAll<HTMLElement>("[data-block-id]")];
		expect(rows.length).toBeGreaterThan(0);
		const anchor = rows.reduce<HTMLElement | undefined>((best, row) => {
			const start = Number(row.dataset.blockStart);
			if (start <= node.scrollTop && (best === undefined || Number(best.dataset.blockStart) < start)) {
				return row;
			}
			return best;
		}, undefined);
		expect(anchor).toBeDefined();
		const id = anchor?.dataset.blockId ?? "";
		const before = Number(anchor?.dataset.blockStart) - node.scrollTop;

		await act(async () => screen.getByText("prepend").click());

		const after = document.querySelector<HTMLElement>(`[data-block-id="${id}"]`);
		expect(after).not.toBeNull();
		expect(Number(after?.dataset.blockStart) - node.scrollTop).toBe(before);
	});

	it("opens the next session at its own newest block", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));

		await act(async () => screen.getByText("switch").click());

		expect(screen.getByText("Bash 505")).toBeInTheDocument();
	});

	it("pins the header of the block under the top edge", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");

		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});

		const header = await screen.findByTestId("sticky-block-header");
		expect(header).toHaveTextContent("Bash 1");
	});

	it("moves the pinned header on to the next block", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");

		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3)) + 5;
			fireEvent.scroll(node);
		});

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
	});

	it("does not pin the header of a block taller than the viewport", async () => {
		await mount([block(1, 1), block(2, 200), block(3, 1)]);
		const node = screen.getByRole("log");

		act(() => {
			node.scrollTop = heightOfBlock(block(1, 1)) + 200;
			fireEvent.scroll(node);
		});

		expect(screen.queryByTestId("sticky-block-header")).not.toBeInTheDocument();
	});

	it("pins a header even when the session is too short to scroll", async () => {
		await mount(range(1, 2));

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");
	});

	it("steps to the next block boundary", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");

		await act(async () => screen.getByRole("button", { name: "Next block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
	});

	it("steps back to the block before a boundary", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3));
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");

		await act(async () => screen.getByRole("button", { name: "Previous block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 1");
	});

	it("steps back to the top of a partly scrolled block first", async () => {
		await mount(range(1, 60, () => 3));
		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = heightOfBlock(block(1, 3)) + 20;
			fireEvent.scroll(node);
		});
		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");

		await act(async () => screen.getByRole("button", { name: "Previous block" }).click());

		expect(screen.getByTestId("sticky-block-header")).toHaveTextContent("Bash 2");
		expect(node.scrollTop).toBe(heightOfBlock(block(1, 3)));
	});

	it("offers a way back to the newest block only once scrolled away", async () => {
		await mount(range(1, 300, (seq) => 1 + (seq % 5)));
		expect(screen.queryByRole("button", { name: "Jump to latest" })).not.toBeInTheDocument();

		const node = screen.getByRole("log");
		act(() => {
			node.scrollTop = 0;
			fireEvent.scroll(node);
		});
		expect(screen.getByRole("button", { name: "Jump to latest" })).toBeInTheDocument();

		await act(async () => screen.getByRole("button", { name: "Jump to latest" }).click());

		expect(screen.getByText("Bash 300")).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Jump to latest" })).not.toBeInTheDocument();
	});
});
