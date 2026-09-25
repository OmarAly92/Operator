import { act, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	clearTerminalTitles,
	setTerminalTitle,
	subscribeTerminalTitles,
	terminalTitle,
	terminalTitleListenerCount,
	useTerminalTitle,
} from "./terminal-titles";

afterEach(() => clearTerminalTitles());

function Title({ handleId }: { handleId?: string }) {
	return <span data-testid="title">{useTerminalTitle(handleId)}</span>;
}

describe("terminal titles", () => {
	it("stores a trimmed title per terminal and forgets an empty one", () => {
		setTerminalTitle("h1", "  Number list  ");
		expect(terminalTitle("h1")).toBe("Number list");
		setTerminalTitle("h1", "");
		expect(terminalTitle("h1")).toBe("");
		expect(terminalTitle(undefined)).toBe("");
	});

	it("notifies only when a title actually changes", () => {
		const listener = vi.fn();
		const off = subscribeTerminalTitles(listener);
		setTerminalTitle("h1", "a");
		setTerminalTitle("h1", "a");
		setTerminalTitle("h1", " a ");
		clearTerminalTitles();
		clearTerminalTitles();
		expect(listener).toHaveBeenCalledTimes(2);
		off();
		setTerminalTitle("h1", "b");
		expect(listener).toHaveBeenCalledTimes(2);
	});

	it("re-renders a component when its terminal's title changes and releases its listener on unmount", () => {
		const before = terminalTitleListenerCount();
		const { unmount } = render(<Title handleId="h1" />);
		expect(screen.getByTestId("title")).toHaveTextContent("");
		act(() => setTerminalTitle("h1", "Refactor"));
		expect(screen.getByTestId("title")).toHaveTextContent("Refactor");
		act(() => setTerminalTitle("h2", "Other"));
		expect(screen.getByTestId("title")).toHaveTextContent("Refactor");
		unmount();
		expect(terminalTitleListenerCount()).toBe(before);
	});
});
