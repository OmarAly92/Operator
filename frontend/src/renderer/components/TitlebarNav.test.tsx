import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { useUiStore } from "../stores/ui-store";
import { TitlebarNav } from "./TitlebarNav";

describe("TitlebarNav", () => {
	beforeEach(() => {
		useUiStore.setState({ isSidebarOpen: true, isCommandPaletteOpen: false, settingsModal: null });
	});

	it("opens global search from the titlebar", () => {
		render(<TitlebarNav />);
		fireEvent.click(screen.getByRole("button", { name: "Search" }));
		expect(useUiStore.getState().isCommandPaletteOpen).toBe(true);
	});

	it("keeps settings and sidebar controls available in fullscreen", () => {
		render(<TitlebarNav isFullScreen />);
		fireEvent.click(screen.getByRole("button", { name: "Settings" }));
		expect(useUiStore.getState().settingsModal).toEqual({ scope: "global" });
		fireEvent.click(screen.getByRole("button", { name: "Collapse sidebar" }));
		expect(useUiStore.getState().isSidebarOpen).toBe(false);
	});

	it("has no board or account buttons", () => {
		render(<TitlebarNav />);
		expect(screen.queryByRole("button", { name: "Board" })).not.toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Account settings" })).not.toBeInTheDocument();
	});
});
