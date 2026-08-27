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
		expect(screen.getByText("Bash 1")).toBeInTheDocument();
		expect(screen.getByText("Bash 3")).toBeInTheDocument();
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
});
