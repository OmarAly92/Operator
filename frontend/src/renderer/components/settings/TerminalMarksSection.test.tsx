import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, test } from "vitest";
import { MAX_TERMINAL_MARKS, terminalMarksStorageKey, type TerminalMark } from "../../lib/terminal-marks";
import { useUiStore } from "../../stores/ui-store";
import { TerminalMarksSection } from "./TerminalMarksSection";

const stored = (): TerminalMark[] => JSON.parse(window.localStorage.getItem(terminalMarksStorageKey) ?? "[]") as TerminalMark[];

afterEach(() => {
	useUiStore.setState({ terminalMarks: [] });
	window.localStorage.clear();
});

test("starts empty and says what a highlight is for", () => {
	render(<TerminalMarksSection />);
	expect(screen.getByText("Highlight words like error in every terminal.")).toBeInTheDocument();
	expect(screen.queryAllByTestId("terminal-mark-row")).toHaveLength(0);
});

test("adds a highlight, types its words and saves them", async () => {
	render(<TerminalMarksSection />);
	await userEvent.click(screen.getByRole("button", { name: "Add highlight" }));
	await userEvent.type(screen.getByRole("textbox", { name: "Highlight 1 words" }), "error");
	expect(useUiStore.getState().terminalMarks).toMatchObject([{ pattern: "error", regex: false, colour: "yellow" }]);
	expect(stored()).toMatchObject([{ pattern: "error", regex: false, colour: "yellow" }]);
	expect(screen.getByText("Words match in any case. Regular expressions match exactly as written.")).toBeInTheDocument();
});

test("switches a highlight to a regular expression and flags one that does not compile", async () => {
	useUiStore.setState({ terminalMarks: [{ id: "a", pattern: "(oops", regex: false, colour: "red" }] });
	render(<TerminalMarksSection />);
	expect(screen.queryByRole("alert")).toBeNull();
	const toggle = screen.getByRole("button", { name: "Use regular expression" });
	expect(toggle).toHaveAttribute("aria-pressed", "false");
	await userEvent.click(toggle);
	expect(useUiStore.getState().terminalMarks[0]!.regex).toBe(true);
	expect(screen.getByRole("button", { name: "Use regular expression" })).toHaveAttribute("aria-pressed", "true");
	expect(screen.getByRole("alert")).toHaveTextContent("Not a valid regular expression");
	expect(screen.getByRole("textbox", { name: "Highlight 1 words" })).toHaveAttribute("aria-invalid", "true");
});

test("changes a highlight's colour from the fixed palette", async () => {
	useUiStore.setState({ terminalMarks: [{ id: "a", pattern: "error", regex: false, colour: "yellow" }] });
	render(<TerminalMarksSection />);
	const trigger = screen.getByRole("button", { name: "Highlight 1 colour" });
	expect(trigger).toHaveTextContent("Yellow");
	await userEvent.click(trigger);
	const items = await screen.findAllByRole("menuitem");
	expect(items.map((item) => item.textContent)).toEqual(["Yellow", "Red", "Green", "Cyan", "Magenta"]);
	await userEvent.click(within(document.body).getByRole("menuitem", { name: "Cyan" }));
	expect(useUiStore.getState().terminalMarks[0]!.colour).toBe("cyan");
	expect(stored()[0]!.colour).toBe("cyan");
});

test("removes a highlight", async () => {
	useUiStore.setState({
		terminalMarks: [
			{ id: "a", pattern: "error", regex: false, colour: "red" },
			{ id: "b", pattern: "warn", regex: false, colour: "yellow" },
		],
	});
	render(<TerminalMarksSection />);
	await userEvent.click(screen.getByRole("button", { name: "Remove highlight 1" }));
	expect(useUiStore.getState().terminalMarks.map((mark) => mark.id)).toEqual(["b"]);
	expect(screen.getAllByTestId("terminal-mark-row")).toHaveLength(1);
});

test("stops offering Add at the cap", () => {
	useUiStore.setState({
		terminalMarks: Array.from({ length: MAX_TERMINAL_MARKS }, (_, index) => ({ id: `m${index}`, pattern: `w${index}`, regex: false, colour: "red" as const })),
	});
	render(<TerminalMarksSection />);
	expect(screen.queryByRole("button", { name: "Add highlight" })).toBeNull();
});
