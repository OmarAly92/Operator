import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { mobileStatus, post } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true,
		host: "192.168.1.20",
		port: 3011,
		password: "pw",
		warning: "",
		tunnel: { state: "live", provider: "cloudflared", url: "https://x.trycloudflare.com", error: "ngrok could not fetch its certificate revocation list", restarts: 0, needsAuthtoken: false, hasAuthtoken: true, lastProvider: "ngrok", fallbackReason: "ngrok could not fetch its certificate revocation list" },
	},
	post: vi.fn(),
}));
vi.mock("../../../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../../../lib/api-client", () => ({
	apiClient: { GET: async () => ({ data: mobileStatus, error: undefined }), POST: post, PUT: vi.fn(), DELETE: vi.fn() },
	apiErrorMessage: () => "failed",
}));

import { useMobileBridge } from "./useMobileBridge";
import { MobilePublicAccessSection } from "./MobilePublicAccessSection";

function Harness() {
	const bridge = useMobileBridge(true);
	return <MobilePublicAccessSection bridge={bridge} />;
}

function renderHarness() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<Harness />
		</QueryClientProvider>,
	);
}

describe("MobilePublicAccessSection", () => {
	test("explains a fallback while live on cloudflared", async () => {
		mobileStatus.tunnel = { state: "live", provider: "cloudflared", url: "https://x.trycloudflare.com", error: "ngrok could not fetch its certificate revocation list", restarts: 0, needsAuthtoken: false, hasAuthtoken: true, lastProvider: "ngrok", fallbackReason: "ngrok could not fetch its certificate revocation list" };
		renderHarness();
		expect(await screen.findByText(/Using cloudflared/)).toBeInTheDocument();
		expect(screen.getByText(/certificate revocation list/)).toBeInTheDocument();
		expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeChecked();
	});

	describe("tunnel switch", () => {
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
				lastProvider: "",
				fallbackReason: "",
			};
		});

		test("shows the tunnel switch while the bridge is on", async () => {
			renderHarness();
			await waitFor(() => expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeTruthy());
		});

		test("disables the tunnel switch while the bridge is off", async () => {
			mobileStatus.enabled = false;
			renderHarness();
			await waitFor(() => {
				const toggle = screen.getByRole("switch", { name: "Reachable outside my network" });
				expect(toggle.getAttribute("disabled")).not.toBeNull();
			});
		});

		test("renders reconnecting without an error treatment", async () => {
			mobileStatus.tunnel.state = "reconnecting";
			mobileStatus.tunnel.restarts = 3;
			renderHarness();
			await waitFor(() => expect(screen.getByText("Reconnecting…")).toBeTruthy());
		});

		test("renders the provider's own message on failure", async () => {
			mobileStatus.tunnel.state = "failed";
			mobileStatus.tunnel.error = "account limit exceeded";
			renderHarness();
			await waitFor(() => expect(screen.getByText("account limit exceeded")).toBeTruthy());
		});

		test("turning the switch off calls the disable route", async () => {
			mobileStatus.tunnel.state = "live";
			mobileStatus.tunnel.url = "https://x.ngrok-free.dev";
			mobileStatus.tunnel.provider = "ngrok";
			renderHarness();

			const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
			await userEvent.click(toggle);

			await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/disable"));
		});

		test("the first enable asks for confirmation before calling the route", async () => {
			window.localStorage.clear();
			renderHarness();

			const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
			await userEvent.click(toggle);

			expect(screen.getByText("Make this desktop reachable from the internet?")).toBeTruthy();
			expect(post).not.toHaveBeenCalled();

			await userEvent.click(screen.getByRole("button", { name: "Make it global" }));
			await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
		});

		test("a remembered acknowledgement skips straight to the route", async () => {
			window.localStorage.setItem("opr.mobile.tunnelConfirmed", "1");
			renderHarness();

			const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
			await userEvent.click(toggle);

			await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
			expect(screen.queryByText("Make this desktop reachable from the internet?")).toBeNull();
		});
	});
});
