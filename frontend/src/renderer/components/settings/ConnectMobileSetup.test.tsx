import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { expect, test } from "vitest";
import { ConnectMobileSetup } from "./ConnectMobileSetup";

test("LAN steps show by default", () => {
	render(<ConnectMobileSetup port={3011} enabled={true} tunnelLive={false} />);
	expect(screen.getByText(/same Wi-Fi as this computer/i)).toBeInTheDocument();
	expect(screen.queryByText(/tailscale ip -4/i)).not.toBeInTheDocument();
});

test("Tailscale mode explains manual entry and echoes the live port", async () => {
	render(<ConnectMobileSetup port={3011} enabled={true} tunnelLive={false} />);
	await userEvent.click(screen.getByRole("radio", { name: "Tailscale" }));
	expect(screen.getByText(/tailscale ip -4/i)).toBeInTheDocument();
	expect(
		screen.getByText((_, el) => el?.textContent?.includes("port 3011") ?? false, { selector: "li" }),
	).toBeInTheDocument();
});

test("segments leave the tab order while the bridge is disabled", () => {
	render(<ConnectMobileSetup port={3011} enabled={false} tunnelLive={false} />);
	expect(screen.getByRole("radio", { name: "LAN" })).toHaveAttribute("tabindex", "-1");
});

test("tunnel steps replace the Wi-Fi and Tailscale steps while the QR carries the public address", () => {
	render(<ConnectMobileSetup port={3011} enabled={true} tunnelLive={true} />);
	expect(screen.getByText(/any network, including cellular/i)).toBeInTheDocument();
	expect(screen.queryByText(/same Wi-Fi/i)).not.toBeInTheDocument();
	expect(screen.queryByRole("radio", { name: "LAN" })).not.toBeInTheDocument();
	expect(screen.queryByRole("radio", { name: "Tailscale" })).not.toBeInTheDocument();
});
