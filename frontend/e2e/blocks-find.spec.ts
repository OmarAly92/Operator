import { expect, test, type Page } from "@playwright/test";
import { installFakeAgent } from "./support/fake-bridge";
import { installFakeBlocksMux } from "./support/fake-blocks-mux";

const SESSION_ID = "find-blocks";
const PROJECT_ID = "find-blocks-proj";

const session = {
	id: SESSION_ID,
	title: "Find blocks",
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
	await installFakeBlocksMux(page);
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

async function emitBatch(page: Page, count: number, fromSeq: number, titleFor: (seq: number) => string): Promise<void> {
	for (let i = 0; i < count; i += 1) {
		const seq = fromSeq + i;
		await emit(page, toolBlock(seq, titleFor(seq), `body ${seq}`));
	}
}

async function openFind(page: Page): Promise<void> {
	const log = page.getByRole("log", { name: "Session blocks" });
	await log.click();
	await page.keyboard.press(process.platform === "darwin" ? "Meta+f" : "Control+f");
	await expect(page.getByRole("search", { name: "Find in blocks" })).toBeVisible();
}

test.describe("blocks find and selection", () => {
	test("the find bar filters the list and reports the hidden count", async ({ page }) => {
		await installHarness(page);
		const log = page.getByRole("log", { name: "Session blocks" });

		await emitBatch(page, 8, 1, (seq) => `Bash ${seq}`);
		await expect(log.getByTestId("session-block")).toHaveCount(8);

		await openFind(page);
		await page.getByRole("textbox", { name: "Find in blocks" }).fill("Bash 3");

		await page.getByRole("button", { name: "Filter results" }).click();
		await expect(log.getByTestId("session-block").filter({ hasText: "Bash 3" })).toHaveCount(1);
		await expect(log.getByTestId("session-block").filter({ hasText: "Bash 1" })).toHaveCount(0);
		await expect(page.getByText(/5 blocks hidden/)).toBeVisible();
	});

	test("next and previous scroll the active match into view and wrap", async ({ page }) => {
		await installHarness(page);
		await emitBatch(page, 12, 1, (seq) => `Bash ${seq}`);

		await openFind(page);
		await page.getByRole("textbox", { name: "Find in blocks" }).fill("Bash");

		const log = page.getByRole("log", { name: "Session blocks" });
		await expect(log.getByTestId("block-match-active")).toHaveCount(1);

		for (let i = 0; i < 11; i += 1) {
			await page.getByRole("button", { name: "Next match" }).click();
		}
		await expect(log.locator('[data-block-id="seq-12"]').getByTestId("block-match-active")).toBeVisible();

		await page.getByRole("button", { name: "Next match" }).click();
		await expect(log.locator('[data-block-id="seq-1"]').getByTestId("block-match-active")).toBeVisible();
		await expect
			.poll(async () => log.evaluate((node) => node.scrollTop))
			.toBe(0);

		await page.getByRole("button", { name: "Previous match" }).click();
		await expect(log.locator('[data-block-id="seq-12"]').getByTestId("block-match-active")).toBeVisible();
		await expect
			.poll(async () =>
				log.evaluate((node) => node.scrollHeight - node.scrollTop - node.clientHeight),
			)
			.toBeLessThanOrEqual(1);
	});

	test("selection mode copies the selected blocks in document order", async ({ page }) => {
		await installHarness(page);
		const log = page.getByRole("log", { name: "Session blocks" });
		await page.context().grantPermissions(["clipboard-read", "clipboard-write"]);

		await emitBatch(page, 5, 1, (seq) => `Bash ${seq}`);

		await openFind(page);
		await page.getByRole("button", { name: "Select" }).click();
		await expect(page.getByText(/0 selected/)).toBeVisible();

		const third = log.getByTestId("session-block").filter({ hasText: "Bash 3" }).first();
		const fifth = log.getByTestId("session-block").filter({ hasText: "Bash 5" }).first();
		await third.getByRole("button", { name: "Select" }).click();
		await fifth.getByRole("button", { name: "Select" }).click();
		await expect(page.getByText(/2 selected/)).toBeVisible();

		await page.getByText(/2 selected/).locator("..").getByRole("button", { name: "Copy" }).click();
		const clipboard = await page.evaluate(() => navigator.clipboard.readText());
		expect(clipboard).toBe("Bash 3\nbody 3\n\nBash 5\nbody 5");
	});
});
