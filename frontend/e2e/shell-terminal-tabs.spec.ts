import { expect, test, type Page } from "@playwright/test";
import { installFakeBridge } from "./support/fake-bridge";
import { installFakeTerminalMux } from "./support/fake-terminal-mux";

function rendererURL(path: string): string {
	const origin = process.env.OPERATOR_E2E_URL;
	return origin ? new URL(path, origin).toString() : path;
}

// Standalone shell terminals (#2822): shells the user opens by hand, with no
// agent session behind them. They render as tabs beside the session's own pane.
// The real pane needs a daemon-spawned PTY, so the preview build stands in with
// an in-memory shell list — enough to cover the parts that live in the renderer:
// which tab is current, and that opening/closing updates the strip.
test("opens, selects, and closes standalone shell terminals from the tab strip", async ({ page }) => {
	await page.goto(rendererURL("/#/projects/opr-demo/sessions/demo-working"));
	await expect(page.getByRole("button", { name: "New terminal" })).toBeVisible();

	const closeButtons = page.getByRole("button", { name: /^Close terminal / });
	const initialCount = await closeButtons.count();

	// The button at the end of the tab strip opens a shell and makes it the
	// active pane. It creates a terminal directly — no menu, no session picker.
	await page.getByRole("button", { name: "New terminal" }).click();
	await expect(page.getByRole("menu")).toHaveCount(0);
	await expect(closeButtons).toHaveCount(initialCount + 1);

	// Selecting the session tab hands the pane back to the agent. Matched by the
	// session's own title: the tab's accessible name is that title, and its
	// title attribute falls back to the label once the strip truncates it.
	// Scoped to the terminal panel: the sidebar carries the same session name.
	const sessionTab = page.getByRole("tab", { name: /^Build screenshot-ready dashboard data/ });
	await sessionTab.click();
	await expect(sessionTab).toHaveAttribute("aria-selected", "true");

	// Closing a shell removes exactly its own tab.
	const closeButton = closeButtons.last();
	await closeButton.locator("..").hover();
	await expect(closeButton).toBeVisible();
	await closeButton.click();
	await expect(closeButtons).toHaveCount(initialCount);
});

test("opens a terminal from the standalone view, where no session view is mounted", async ({ page }) => {
	await page.goto(rendererURL("/#/terminals"));
	await expect(page.getByRole("button", { name: "New terminal" })).toBeVisible();

	await page.getByRole("button", { name: "New terminal" }).click();

	await expect(page).toHaveURL(/#\/terminals$/);
	await expect(page.getByRole("button", { name: /^Close terminal / })).not.toHaveCount(0);
});

test("shows an empty state once every standalone terminal is closed", async ({ page }) => {
	await page.goto(rendererURL("/#/terminals"));

	// Wait for the strip to render before counting — a count taken mid-mount
	// reads 0 and would skip the loop entirely, leaving the terminals open.
	const closeButtons = page.getByRole("button", { name: /^Close terminal / });
	await expect(closeButtons).not.toHaveCount(0);

	// Close one at a time, asserting the strip shrank before the next click: the
	// close is async, so clicking on a stale count would race the re-render.
	for (let remaining = await closeButtons.count(); remaining > 0; remaining--) {
		await closeButtons.first().click();
		await expect(closeButtons).toHaveCount(remaining - 1);
	}

	await expect(page.getByText("No terminals open")).toBeVisible();
});

type DurableBlockFixture = {
	command: string;
	cwd: string;
	exitCode: number;
	id: string;
	raw: string;
};

function terminalPrompt(id: string, cwd: string, branch: string): string {
	return (
		`\x1b]7000;v=1;id=${id};cwd=${encodeURIComponent(cwd)};branch=${encodeURIComponent(branch)};start_ms=1788177600000\x07` +
		"\x1b]133;A\x07$ \x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07"
	);
}

function terminalCompletion(id: string, command: string, output: string, exitCode: number): string {
	return (
		"\x1b]7000;v=1;input-released=1\x07" +
		`\x1b]7000;v=1;id=${id};cmd=${encodeURIComponent(command)}\x07` +
		`\x1b]133;C\x07${output}\r\n` +
		`\x1b]7000;v=1;id=${id};exit=${exitCode};end_ms=1788177600250\x07` +
		`\x1b]133;D;${exitCode}\x07`
	);
}

async function terminalBlockSnapshot(page: Page) {
	return page.locator("[data-terminal-block-id]").evaluateAll((blocks) =>
		blocks.map((block) => {
			const header = block.querySelector<HTMLElement>(".terminal-block-header");
			return {
				text: (block as HTMLElement).innerText,
				status: header?.dataset.blockStatus ?? null,
				command: header?.querySelector<HTMLElement>(".terminal-block-command")?.innerText ?? null,
				cwd: header?.querySelector<HTMLElement>(".terminal-block-cwd")?.innerText ?? null,
				branch: header?.querySelector<HTMLElement>(".terminal-block-branch")?.innerText ?? null,
				exit: header?.querySelector<HTMLElement>(".terminal-block-exit")?.innerText ?? null,
				runs: Array.from(block.querySelectorAll<HTMLElement>("[data-terminal-run]"))
					.filter((run) => run.innerText.length > 0)
					.map((run) => {
						const style = getComputedStyle(run);
						return {
							text: run.innerText,
							color: style.color,
							fontStyle: style.fontStyle,
							fontWeight: style.fontWeight,
							textDecoration: style.textDecorationLine,
						};
					}),
			};
		}),
	);
}

test("restores durable shell blocks with live text, styling, metadata, and exits unchanged", async ({ page }) => {
	await installFakeBridge(page, { daemonState: "ready", daemonPort: 8080 });
	await installFakeTerminalMux(page, {});

	const definitions = [
		{ command: "printf 'success-output\\n'", cwd: "/workspace/repo", branch: "main", output: "success-output", exitCode: 0 },
		{ command: "sh -c 'printf failure-output; exit 7'", cwd: "/workspace/repo", branch: "main", output: "failure-output", exitCode: 7 },
		{ command: "cd /tmp", cwd: "/workspace/repo", branch: "main", output: "", exitCode: 0 },
		{ command: "printf '\\033[31mstyled-output\\033[0m\\n'", cwd: "/tmp", branch: "", output: "\x1b[31mstyled-output\x1b[0m", exitCode: 0 },
	];
	const fixtures: DurableBlockFixture[] = definitions.map((definition, index) => {
		const id = `shellterm-demo-1-${index + 1}`;
		return {
			command: definition.command,
			cwd: definition.cwd,
			exitCode: definition.exitCode,
			id,
			raw:
				terminalPrompt(id, definition.cwd, definition.branch) +
				terminalCompletion(id, definition.command, definition.output, definition.exitCode),
		};
	});

	let history: DurableBlockFixture[] = [];
	await page.route("**/api/v1/shell-terminals/shellterm-demo-1/blocks*", async (route) => {
		await route.fulfill({
			contentType: "application/json",
			body: JSON.stringify(
				history.map((block, index) => ({
					captureEpoch: "e2e-epoch",
					command: block.command,
					createdAt: "2026-08-31T12:00:00Z",
					cwd: block.cwd,
					endOffset: index * 1000 + block.raw.length,
					exitCode: block.exitCode,
					finishedAt: "2026-08-31T12:00:00.250Z",
					gitBranch: definitions[index]!.branch,
					rawOutput: Buffer.from(block.raw).toString("base64"),
					shellKind: "zsh",
					shellVersion: "5.9",
					sourceId: block.id,
					startOffset: index * 1000,
					startedAt: "2026-08-31T12:00:00Z",
					terminalId: "shellterm-demo-1",
					truncatedBytes: 0,
					truncatedLines: 0,
				})),
			),
		});
	});

	await page.goto(rendererURL("/#/terminals"));
	await expect(page.locator(".terminal-editor")).toBeVisible();

	await page.evaluate(
		({ handleId, text }) => window.__aoFakeTerminalMux!.emit(handleId, text),
		{ handleId: "shellterm-demo-1", text: terminalPrompt(fixtures[0]!.id, definitions[0]!.cwd, definitions[0]!.branch) },
	);

	for (let index = 0; index < fixtures.length; index += 1) {
		const fixture = fixtures[index]!;
		await page.locator(".terminal-editor").focus();
		await page.keyboard.type(fixture.command);
		await page.keyboard.press("Enter");
		await expect
			.poll(async () =>
				page.evaluate(
					(handleId) => window.__aoFakeTerminalMux!.stats().inputs[handleId]?.join("") ?? "",
					"shellterm-demo-1",
				),
			)
			.toContain(`${fixture.command}\n`);
		const next = definitions[index + 1];
		const text =
			terminalCompletion(fixture.id, fixture.command, definitions[index]!.output, fixture.exitCode) +
			(next ? terminalPrompt(fixtures[index + 1]!.id, next.cwd, next.branch) : "");
		await page.evaluate(
			({ handleId, text }) => window.__aoFakeTerminalMux!.emit(handleId, text),
			{ handleId: "shellterm-demo-1", text },
		);
	}

	await expect(page.locator("[data-terminal-block-id]")).toHaveCount(4);
	await expect.poll(async () => (await terminalBlockSnapshot(page)).map((block) => block.status)).toEqual([
		"succeeded",
		"failed",
		"succeeded",
		"succeeded",
	]);
	const beforeReload = await terminalBlockSnapshot(page);
	expect(beforeReload.map((block) => block.status)).toEqual(["succeeded", "failed", "succeeded", "succeeded"]);
	expect(beforeReload.map((block) => block.command)).toEqual(definitions.map((block) => block.command));
	expect(beforeReload.map((block) => block.cwd)).toEqual(["/workspace/repo", "/workspace/repo", "/workspace/repo", "/tmp"]);
	expect(beforeReload.map((block) => block.branch)).toEqual(["main", "main", "main", null]);
	expect(beforeReload.map((block) => block.exit)).toEqual([null, "exit 7", null, null]);
	expect(beforeReload[3]!.runs.some((run) => run.text.includes("styled-output") && run.color !== "rgb(255, 255, 255)")).toBe(true);

	history = fixtures;
	await page.reload();
	await expect(page.locator("[data-terminal-block-id]")).toHaveCount(4);
	await expect.poll(() => terminalBlockSnapshot(page)).toEqual(beforeReload);
});
