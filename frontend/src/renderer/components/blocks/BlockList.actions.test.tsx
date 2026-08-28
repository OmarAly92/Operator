import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SessionBlock } from "../../lib/session-block";
import { installVirtualLayout } from "../../test/virtual-layout";
import { BlockList } from "./BlockList";

function permission(id: string, status: "blocked" | "ok" = "blocked"): SessionBlock {
	return {
		id,
		firstSeq: 1,
		lastSeq: 1,
		kind: "permission",
		status,
		title: "Permission requested",
		body: "Bash\ngit branch -D feat/x",
		truncatedLines: 0,
		redacted: false,
	};
}

function prompt(id: string, turnId?: string): SessionBlock {
	return {
		id,
		firstSeq: 1,
		lastSeq: 1,
		kind: "prompt",
		status: "ok",
		turnId,
		title: "Prompt",
		body: "run the tests",
		truncatedLines: 0,
		redacted: false,
	};
}

let teardown: () => void;
let currentBlocks: SessionBlock[] = [];

beforeEach(() => {
	teardown = installVirtualLayout({ heights: () => currentBlocks.map(() => 80) });
});
afterEach(() => {
	teardown();
	cleanup();
});

function renderList(props: Partial<Parameters<typeof BlockList>[0]> & { blocks: SessionBlock[] }) {
	currentBlocks = props.blocks;
	return render(<BlockList sessionId="s-1" {...props} />);
}

describe("BlockList action slot", () => {
	it("renders whatever the caller supplies for a block", () => {
		renderList({
			blocks: [permission("req-1")],
			renderActions: (block) =>
				block.kind === "permission" ? <button type="button">Allow once</button> : null,
		});

		expect(screen.getByText("Allow once")).toBeInTheDocument();
	});

	it("draws no action row when the caller supplies nothing", () => {
		renderList({ blocks: [permission("req-1")] });

		expect(screen.queryByTestId("block-actions")).not.toBeInTheDocument();
	});

	it("draws no action row when the caller returns null for this block", () => {
		renderList({ blocks: [permission("req-1")], renderActions: () => null });

		expect(screen.queryByTestId("block-actions")).not.toBeInTheDocument();
	});

	it("passes each block to the caller so it can decide per block", () => {
		const seen: string[] = [];
		renderList({
			blocks: [prompt("p-1"), permission("req-1")],
			renderActions: (block) => {
				seen.push(block.id);
				return null;
			},
		});

		expect(seen).toContain("p-1");
		expect(seen).toContain("req-1");
	});

	it("wires the caller's click handler", () => {
		const onClick = vi.fn();
		renderList({
			blocks: [permission("req-1")],
			renderActions: () => (
				<button data-testid="allow" onClick={onClick} type="button">
					Allow
				</button>
			),
		});

		fireEvent.click(screen.getByTestId("allow"));
		expect(onClick).toHaveBeenCalledTimes(1);
	});
});

