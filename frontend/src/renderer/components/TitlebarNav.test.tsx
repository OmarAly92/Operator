import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useUiStore } from "../stores/ui-store";
import { TitlebarNav } from "./TitlebarNav";

vi.mock("../lib/platform", () => ({
	isLinuxPlatform: () => false,
	isMacPlatform: () => true,
}));

describe("TitlebarNav", () => {
	beforeEach(() => {
		useUiStore.setState({ isSidebarOpen: true });
	});

	it("uses the compact sidebar-aligned chrome row in native fullscreen", () => {
		const { container } = render(<TitlebarNav isFullScreen />);

		const nav = container.querySelector('[data-slot="titlebar-nav"]');
		expect(nav).toHaveClass("left-titlebar-cluster-left-fullscreen", "h-traffic-light-clearance-fullscreen", "top-0");
		expect(nav).not.toHaveClass("h-traffic-light-clearance");
		// The history arrows are gone; the sidebar toggle is the whole cluster.
		expect(screen.queryByRole("button", { name: /^Go (back|forward)$/ })).not.toBeInTheDocument();
	});

	it("centers collapsed fullscreen navigation on the inset session topbar", () => {
		useUiStore.setState({ isSidebarOpen: false });
		const { container } = render(<TitlebarNav hasSessionTopbar isFullScreen />);

		const nav = container.querySelector('[data-slot="titlebar-nav"]');
		expect(nav).toHaveClass("top-1.5", "left-titlebar-cluster-left-fullscreen");
		expect(nav).not.toHaveClass("top-0");
	});

	it("keeps expanded fullscreen navigation at the top of the sidebar chrome row", () => {
		const { container } = render(<TitlebarNav hasSessionTopbar isFullScreen />);

		const nav = container.querySelector('[data-slot="titlebar-nav"]');
		expect(nav).toHaveClass("top-0");
		expect(nav).not.toHaveClass("top-1.5");
	});

	it("retains the traffic-light geometry in a windowed macOS shell", () => {
		const { container } = render(<TitlebarNav />);

		const nav = container.querySelector('[data-slot="titlebar-nav"]');
		expect(nav).toHaveClass("left-titlebar-cluster-left", "h-traffic-light-clearance", "top-0");
	});
});
