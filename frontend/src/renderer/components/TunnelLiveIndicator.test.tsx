import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { tunnelStatus } = vi.hoisted(() => ({
	tunnelStatus: { current: undefined as undefined | { state: string; provider: string } },
}));

vi.mock("../hooks/useMobileTunnelStatus", () => ({
	useMobileTunnelStatus: () => tunnelStatus.current,
}));

import { TunnelLiveRailButton, TunnelLiveRow } from "./TunnelLiveIndicator";
import { TooltipProvider } from "./ui/tooltip";
import { useUiStore } from "../stores/ui-store";

function tunnel(state: string, provider = "ngrok") {
	return { state, provider, url: "", error: "", restarts: 0, needsAuthtoken: false, hasAuthtoken: false };
}

describe("TunnelLiveIndicator", () => {
	beforeEach(() => {
		tunnelStatus.current = undefined;
		useUiStore.setState({ settingsModal: null });
	});

	test("renders nothing while there is no tunnel status", () => {
		const { container } = render(<TunnelLiveRow tabIndex={0} />);
		expect(container.innerHTML).toBe("");
	});

	test.each(["off", "failed"])("renders nothing while the tunnel is %s", (state) => {
		tunnelStatus.current = tunnel(state);
		const { container } = render(<TunnelLiveRow tabIndex={0} />);
		expect(container.innerHTML).toBe("");
	});

	test("names the live provider", () => {
		tunnelStatus.current = tunnel("live", "cloudflared");
		render(<TunnelLiveRow tabIndex={0} />);
		expect(screen.getByText("Reachable from anywhere via cloudflared")).toBeTruthy();
	});

	test.each([
		["downloading", "Preparing the tunnel…"],
		["starting", "Opening a public address…"],
		["reconnecting", "Reconnecting…"],
	])("stays visible while %s, because the machine is about to be or still is exposed", (state, copy) => {
		tunnelStatus.current = tunnel(state);
		render(<TunnelLiveRow tabIndex={0} />);
		expect(screen.getByText(copy)).toBeTruthy();
	});

	test("clicking the row opens Connect Mobile directly", async () => {
		tunnelStatus.current = tunnel("live");
		render(<TunnelLiveRow tabIndex={0} />);

		await userEvent.click(screen.getByRole("button", { name: "Reachable outside my network" }));

		expect(useUiStore.getState().settingsModal).toEqual({ scope: "global", section: "mobile" });
	});

	test("the collapsed rail button opens Connect Mobile too", async () => {
		tunnelStatus.current = tunnel("live");
		render(
			<TooltipProvider>
				<TunnelLiveRailButton tabIndex={0} />
			</TooltipProvider>,
		);

		await userEvent.click(screen.getByRole("button", { name: "Reachable outside my network" }));

		expect(useUiStore.getState().settingsModal).toEqual({ scope: "global", section: "mobile" });
	});
});
