import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useEffect } from "react";
import { describe, expect, it } from "vitest";
import { pastePreviewLines, usePasteConfirm, type PasteConfirmFn } from "./usePasteConfirm";

function Harness({ onReady }: { onReady: (confirm: PasteConfirmFn) => void }) {
	const { confirmPaste, dialog } = usePasteConfirm();
	useEffect(() => {
		onReady(confirmPaste);
	}, [confirmPaste, onReady]);
	return dialog;
}

function mount() {
	let confirm: PasteConfirmFn = async () => false;
	const view = render(
		<Harness
			onReady={(next) => {
				confirm = next;
			}}
		/>,
	);
	const ask = (preview: string, reason: Parameters<PasteConfirmFn>[1]) => {
		let answer: Promise<boolean> = Promise.resolve(false);
		act(() => {
			answer = confirm(preview, reason);
		});
		return answer;
	};
	return { view, ask };
}

describe("usePasteConfirm", () => {
	it("shows the reason and the paste, and answers yes on Paste", async () => {
		const { ask } = mount();
		const answer = ask("git pull\nnpm install", "newline");
		const dialog = screen.getByRole("dialog", { name: "Paste into the terminal?" });
		expect(dialog).toHaveTextContent("It has more than one line, so each line may run as a command.");
		expect(screen.getByTestId("paste-preview").textContent).toBe("git pull\nnpm install");
		await userEvent.click(screen.getByRole("button", { name: "Paste" }));
		await expect(answer).resolves.toBe(true);
		await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
	});

	it("answers no on Cancel", async () => {
		const { ask } = mount();
		const answer = ask("one\ntwo", "newline");
		await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
		await expect(answer).resolves.toBe(false);
	});

	it("answers no when the dialog is closed", async () => {
		const { ask } = mount();
		const answer = ask("one\ntwo", "newline");
		await userEvent.click(screen.getByRole("button", { name: "Close dialog" }));
		await expect(answer).resolves.toBe(false);
	});

	it("answers an earlier request no when a new one arrives", async () => {
		const { ask } = mount();
		const first = ask("first\nline", "newline");
		const second = ask("second\nline", "newline");
		await expect(first).resolves.toBe(false);
		expect(screen.getByTestId("paste-preview").textContent).toBe("second\nline");
		await userEvent.click(screen.getByRole("button", { name: "Paste" }));
		await expect(second).resolves.toBe(true);
	});

	it("answers no when the terminal goes away while asking", async () => {
		const { view, ask } = mount();
		const answer = ask("one\ntwo", "newline");
		view.unmount();
		await expect(answer).resolves.toBe(false);
	});

	it("shows control characters as caret notation with the control reason", () => {
		const { ask } = mount();
		void ask("echo ^[[31m", "control");
		expect(screen.getByRole("dialog")).toHaveTextContent(
			"It contains control characters (shown as ^ below) that act like key presses.",
		);
		expect(screen.getByTestId("paste-preview").textContent).toBe("echo ^[[31m");
	});

	it("limits the preview to five lines of 200 characters and counts the rest", () => {
		const long = "x".repeat(250);
		expect(pastePreviewLines(`${long}\n2\n3\n4\n5\n6\n7`)).toEqual({
			lines: [`${"x".repeat(200)}…`, "2", "3", "4", "5"],
			hidden: 2,
		});
		expect(pastePreviewLines("only")).toEqual({ lines: ["only"], hidden: 0 });
		const { ask } = mount();
		void ask("1\n2\n3\n4\n5\n6\n7", "newline");
		expect(screen.getByTestId("paste-preview").textContent).toBe("1\n2\n3\n4\n5");
		expect(screen.getByRole("dialog")).toHaveTextContent("…and 2 more lines");
	});
});
