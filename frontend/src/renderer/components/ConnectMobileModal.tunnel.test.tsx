import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { mobileStatus, post } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true,
		host: "192.168.1.20",
		port: 3011,
		password: "hunter2secret",
		warning: "",
		tunnel: {
			state: "off",
			provider: "",
			url: "",
			error: "",
			restarts: 0,
			needsAuthtoken: false,
			hasAuthtoken: false,
		},
	},
	post: vi.fn(),
}));

vi.mock("../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../lib/api-client", () => ({
	apiClient: {
		GET: async () => ({ data: mobileStatus, error: undefined }),
		POST: post,
	},
	apiErrorMessage: () => "failed",
}));

import { ConnectMobileModal, pairingPayloadV2, tunnelRefetchInterval } from "./ConnectMobileModal";

function renderModal() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<ConnectMobileModal open onOpenChange={vi.fn()} />
		</QueryClientProvider>,
	);
}

describe("Connect Mobile tunnel toggle", () => {
	beforeEach(() => {
		post.mockReset();
		post.mockResolvedValue({ data: mobileStatus, error: undefined });
		mobileStatus.enabled = true;
		mobileStatus.tunnel = {
			state: "off",
			provider: "",
			url: "",
			error: "",
			restarts: 0,
			needsAuthtoken: false,
			hasAuthtoken: false,
		};
	});

	test("shows the tunnel switch while the bridge is on", async () => {
		renderModal();
		await waitFor(() => expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeTruthy());
	});

	test("disables the tunnel switch while the bridge is off", async () => {
		mobileStatus.enabled = false;
		renderModal();
		await waitFor(() => {
			const toggle = screen.getByRole("switch", { name: "Reachable outside my network" });
			expect(toggle.getAttribute("disabled")).not.toBeNull();
		});
	});

	test("QR stays on the LAN address until the tunnel is live", async () => {
		mobileStatus.tunnel.state = "starting";
		renderModal();
		await waitFor(() => expect(screen.getByText("Opening a public address…")).toBeTruthy());
		expect(screen.getByText("192.168.1.20:3011")).toBeTruthy();
	});

	test("QR and address swap to the tunnel URL once live", async () => {
		mobileStatus.tunnel.state = "live";
		mobileStatus.tunnel.provider = "ngrok";
		mobileStatus.tunnel.url = "https://imagines-livestock-widely.ngrok-free.dev";
		renderModal();

		await waitFor(() => expect(screen.getByText("https://imagines-livestock-widely.ngrok-free.dev")).toBeTruthy());
		expect(screen.getByText("Reachable from anywhere via ngrok")).toBeTruthy();
		expect(screen.queryByText("192.168.1.20:3011")).toBeNull();
	});

	test("renders reconnecting without an error treatment", async () => {
		mobileStatus.tunnel.state = "reconnecting";
		mobileStatus.tunnel.restarts = 3;
		renderModal();
		await waitFor(() => expect(screen.getByText("Reconnecting…")).toBeTruthy());
	});

	test("renders the provider's own message on failure", async () => {
		mobileStatus.tunnel.state = "failed";
		mobileStatus.tunnel.error = "account limit exceeded";
		renderModal();
		await waitFor(() => expect(screen.getByText("account limit exceeded")).toBeTruthy());
	});

	test("v2 payload carries the url and password, and no host or port", () => {
		const payload = JSON.parse(pairingPayloadV2("https://x.ngrok-free.dev", "pw"));
		expect(payload).toEqual({ v: 2, url: "https://x.ngrok-free.dev", password: "pw" });
	});

	test("turning the switch off calls the disable route", async () => {
		mobileStatus.tunnel.state = "live";
		mobileStatus.tunnel.url = "https://x.ngrok-free.dev";
		mobileStatus.tunnel.provider = "ngrok";
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/disable"));
	});

	test("the first enable asks for confirmation before calling the route", async () => {
		window.localStorage.clear();
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		expect(screen.getByText("Make this desktop reachable from the internet?")).toBeTruthy();
		expect(post).not.toHaveBeenCalled();

		await userEvent.click(screen.getByRole("button", { name: "Make it global" }));
		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
	});

	test("a remembered acknowledgement skips straight to the route", async () => {
		window.localStorage.setItem("opr.mobile.tunnelConfirmed", "1");
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
		expect(screen.queryByText("Make this desktop reachable from the internet?")).toBeNull();
	});

	test("a live tunnel keeps polling so a later drop is observed", () => {
		expect(tunnelRefetchInterval("live")).toBe(5000);
	});

	test("transitional states poll fast and terminal ones stop", () => {
		expect(tunnelRefetchInterval("starting")).toBe(1000);
		expect(tunnelRefetchInterval("downloading")).toBe(1000);
		expect(tunnelRefetchInterval("reconnecting")).toBe(1000);
		expect(tunnelRefetchInterval("failed")).toBe(false);
		expect(tunnelRefetchInterval("off")).toBe(false);
		expect(tunnelRefetchInterval(undefined)).toBe(false);
	});
});
