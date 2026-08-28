import { expect, test, type Page } from "@playwright/test";
import { installFakeAgent } from "./support/fake-bridge";
import { installFakeBlocksMux } from "./support/fake-blocks-mux";

const SESSION_ID = "viewport-blocks";
const PROJECT_ID = "viewport-blocks-proj";

const session = {
	id: SESSION_ID,
	title: "Blocks viewport",
	mode: "tui" as const,
	provider: "claude-code",
	activity: "active" as const,
};

function toolBlock(seq: number, title: string, body: string) {
	return {
		ch: "blocks",
		createdAt: new Date(Date.UTC(2026, 7, 28, 10, 0, seq)).toISOString(),
		harness: "claude-code",
		hookVersion: "1",
		kind: "tool_complete",
		seq,
		sessionId: SESSION_ID,
		text: body,
		toolName: title,
		truncatedLines: 0,
	};
}

async function installHarness(page: Page): Promise<void> {
	await page.setViewportSize({ width: 1280, height: 800 });
	await installFakeAgent(page, {
		projectId: PROJECT_ID,
		projectName: PROJECT_ID,
		workers: [session],
	});
	await installFakeBlocksMux(page, { virtualizationThreshold: 4 });
	await page.goto(`/#/projects/${PROJECT_ID}/sessions/${SESSION_ID}`);
	await page.getByText(/No blocks yet|Loading/).waitFor({ state: "visible" }).catch(() => undefined);
	const showBlocks = page.getByRole("button", { name: "Show blocks" });
	if (await showBlocks.isVisible().catch(() => false)) {
		await showBlocks.click();
	}
}

async function emit(page: Page, record: ReturnType<typeof toolBlock>): Promise<void> {
	await page.evaluate(
		({ sessionId, record }) => {
			window.__aoFakeBlocksMux!.emit(sessionId, record);
		},
		{ sessionId: SESSION_ID, record },
	);
}

async function emitBatch(page: Page, count: number, fromSeq: number, label: string): Promise<void> {
	for (let i = 0; i < count; i += 1) {
		const seq = fromSeq + i;
		await emit(page, toolBlock(seq, `${label} ${seq}`, `body of ${label} ${seq}`));
	}
}

test.describe("blocks viewport", () => {
	test("appended blocks follow the tail while pinned", async ({ page }) => {
		await installHarness(page);
		await emitBatch(page, 12, 1, "Bash");

		const log = page.getByRole("log", { name: "Session blocks" });
		await expect(log).toBeVisible();
		await expect(log.getByTestId("session-block").filter({ hasText: "Bash 12" })).toHaveCount(1);

		await emit(page, toolBlock(13, "Bash 13", "newest block"));
		await expect(log.getByTestId("session-block").filter({ hasText: "Bash 13" })).toHaveCount(1);
		await expect
			.poll(async () =>
				log.evaluate((node) => node.scrollHeight - node.scrollTop - node.clientHeight),
			)
			.toBeLessThanOrEqual(1);
	});

	test("appended blocks do not move the viewport while scrolled up", async ({ page }) => {
		await installHarness(page);
		await emitBatch(page, 12, 1, "Bash");

		const log = page.getByRole("log", { name: "Session blocks" });
		await expect(log).toBeVisible();
		await log.evaluate((node) => {
			node.scrollTop = 0;
			node.dispatchEvent(new Event("scroll"));
		});
		const scrollTopBefore = await log.evaluate((node) => node.scrollTop);

		await emit(page, toolBlock(13, "Bash 13", "newest block"));
		await expect(page.getByRole("button", { name: "Jump to latest" })).toBeVisible();
		const scrollTopAfter = await log.evaluate((node) => node.scrollTop);
		expect(scrollTopAfter).toBe(scrollTopBefore);
	});

	test("Load older prepends without moving the read position", async ({ page }) => {
		await installHarness(page);
		await emitBatch(page, 12, 1, "Bash");

		const log = page.getByRole("log", { name: "Session blocks" });
		await expect(log).toBeVisible();
		await log.evaluate((node) => {
			node.scrollTop = 200;
			node.dispatchEvent(new Event("scroll"));
		});

		const anchorIdBefore = await log.evaluate((node) => {
			const rows = [...node.querySelectorAll<HTMLElement>("[data-block-id]")];
			const anchor = rows.reduce<HTMLElement | undefined>((best, row) => {
				const start = Number(row.dataset.blockStart ?? "0");
				if (start <= node.scrollTop && (best === undefined || Number(best.dataset.blockStart) < start)) {
					return row;
				}
				return best;
			}, undefined);
			return anchor?.dataset.blockId ?? "";
		});
		const readOffsetBefore = await log.evaluate((node, id) => {
			const row = node.querySelector<HTMLElement>(`[data-block-id="${id}"]`);
			return row === null ? 0 : Number(row.dataset.blockStart) - node.scrollTop;
		}, anchorIdBefore);

		const loadOlder = page.getByRole("button", { name: "Load older blocks" });
		if (await loadOlder.isVisible().catch(() => false)) {
			await loadOlder.click();
		}

		await emitBatch(page, 4, -5, "Old");
		await emit(page, { ...toolBlock(-1, "Old -1", "oldest"), seq: -1 });

		await expect
			.poll(async () =>
				page.evaluate(
					({ sessionId }) => window.__aoFakeBlocksMux!.stats().emit[sessionId] ?? 0,
					{ sessionId: SESSION_ID },
				),
			)
			.toBeGreaterThanOrEqual(5);
		await expect(log.locator(`[data-block-id="${anchorIdBefore}"]`)).toBeAttached();

		const anchorAfter = await log.evaluate((node, anchorId) => {
			const row = node.querySelector<HTMLElement>(`[data-block-id="${anchorId}"]`);
			if (row === null) return null;
			return { blockStart: Number(row.dataset.blockStart), scrollTop: node.scrollTop };
		}, anchorIdBefore);
		expect(anchorAfter).not.toBeNull();
		expect(anchorAfter!.blockStart - anchorAfter!.scrollTop).toBe(readOffsetBefore);
	});

	test("the sticky header appears for a short block and is suppressed when the block is taller than the viewport", async ({
		page,
	}) => {
		await page.setViewportSize({ width: 1280, height: 320 });
		await installFakeAgent(page, {
			projectId: PROJECT_ID,
			projectName: PROJECT_ID,
			workers: [session],
		});
		await installFakeBlocksMux(page, { virtualizationThreshold: 4 });
		await page.goto(`/#/projects/${PROJECT_ID}/sessions/${SESSION_ID}`);
		await page.getByText(/No blocks yet|Loading/).waitFor({ state: "visible" }).catch(() => undefined);
		const showBlocks = page.getByRole("button", { name: "Show blocks" });
		if (await showBlocks.isVisible().catch(() => false)) {
			await showBlocks.click();
		}
		await emit(page, toolBlock(1, "Short", "single line"));
		await emit(page, toolBlock(2, "Tall", "x".repeat(20_000)));

		const log = page.getByRole("log", { name: "Session blocks" });
		await expect(log).toBeVisible();
		await log.evaluate((node) => {
			node.scrollTop = 0;
			node.dispatchEvent(new Event("scroll"));
		});

		await expect
			.poll(async () => log.evaluate((node) => node.scrollHeight - node.clientHeight))
			.toBeGreaterThan(0);
		const sticky = page.getByTestId("sticky-block-header");
		await expect(sticky).toHaveCount(1);
		await expect(sticky).toContainText("Short");

		await log.evaluate((node) => {
			node.scrollTop = node.scrollHeight;
			node.dispatchEvent(new Event("scroll"));
		});
		await expect(page.getByTestId("sticky-block-header")).toHaveCount(0);
	});
});
