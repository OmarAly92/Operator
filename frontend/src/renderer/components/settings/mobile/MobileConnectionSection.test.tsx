import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test, vi } from "vitest";

const { mobileStatus, disableDeferred } = vi.hoisted(() => {
	const deferred: { resolve: (value: unknown) => void } = { resolve: () => {} };
	return {
		mobileStatus: {
			enabled: true, host: "192.168.1.20", port: 3011, password: "pw", warning: "",
			tunnel: undefined as
				| {
						state: string;
						provider: string;
						url: string;
						error: string;
						restarts: number;
						needsAuthtoken: boolean;
						hasAuthtoken: boolean;
				  }
				| undefined,
		},
		disableDeferred: deferred,
	};
});
vi.mock("../../../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../../../lib/api-client", () => ({
	apiClient: {
		GET: async () => ({ data: mobileStatus, error: undefined }),
		POST: vi.fn((path: string) => {
			if (path === "/api/v1/mobile/disable") {
				return new Promise((resolve) => {
					disableDeferred.resolve = resolve;
				});
			}
			return Promise.resolve({ data: mobileStatus, error: undefined });
		}),
		PUT: vi.fn(),
		DELETE: vi.fn(),
	},
	apiErrorMessage: () => "failed",
}));

import { useMobileBridge } from "./useMobileBridge";
import { MobileConnectionSection } from "./MobileConnectionSection";
import { MobilePublicAccessSection } from "./MobilePublicAccessSection";

function Harness() {
	const bridge = useMobileBridge(true);
	return <MobileConnectionSection bridge={bridge} />;
}

function CombinedHarness() {
	const bridge = useMobileBridge(true);
	return (
		<MobileConnectionSection bridge={bridge}>
			<MobilePublicAccessSection bridge={bridge} />
		</MobileConnectionSection>
	);
}

function renderCombined() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<CombinedHarness />
		</QueryClientProvider>,
	);
}

describe("MobileConnectionSection", () => {
	test("regenerate spinner stays hidden while a disable is in flight", async () => {
		const user = userEvent.setup();
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		render(
			<QueryClientProvider client={client}>
				<Harness />
			</QueryClientProvider>,
		);

		const regenerateButton = await screen.findByRole("button", { name: "Regenerate password" });
		await user.click(screen.getByRole("switch", { name: "Enable mobile" }));

		expect(regenerateButton).toBeDisabled();
		expect(regenerateButton.querySelector("svg")).toBeNull();

		disableDeferred.resolve({ data: {}, error: undefined });
	});

	test("once live, the dialog stops telling the user to join the same Wi-Fi", async () => {
		mobileStatus.tunnel = {
			state: "live",
			provider: "ngrok",
			url: "https://imagines-livestock-widely.ngrok-free.dev",
			error: "",
			restarts: 0,
			needsAuthtoken: false,
			hasAuthtoken: true,
		};
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		render(
			<QueryClientProvider client={client}>
				<Harness />
			</QueryClientProvider>,
		);

		await waitFor(() => expect(screen.getByText(/any network, including cellular/i)).toBeTruthy());
		expect(screen.queryByText(/same Wi-Fi/i)).toBeNull();

		mobileStatus.tunnel = undefined;
	});

	describe("combined with the public-access switch", () => {
		test("QR stays on the LAN address until the tunnel is live", async () => {
			mobileStatus.tunnel = {
				state: "starting",
				provider: "",
				url: "",
				error: "",
				restarts: 0,
				needsAuthtoken: false,
				hasAuthtoken: false,
			};
			renderCombined();
			await waitFor(() => expect(screen.getByText("Opening a public address…")).toBeTruthy());
			expect(screen.getByText("192.168.1.20:3011")).toBeTruthy();
			mobileStatus.tunnel = undefined;
		});

		test("QR and address swap to the tunnel URL once live", async () => {
			mobileStatus.tunnel = {
				state: "live",
				provider: "ngrok",
				url: "https://imagines-livestock-widely.ngrok-free.dev",
				error: "",
				restarts: 0,
				needsAuthtoken: false,
				hasAuthtoken: false,
			};
			renderCombined();

			await waitFor(() => expect(screen.getByText("https://imagines-livestock-widely.ngrok-free.dev")).toBeTruthy());
			expect(screen.getByText("Reachable from anywhere via ngrok")).toBeTruthy();
			expect(screen.queryByText("192.168.1.20:3011")).toBeNull();
			mobileStatus.tunnel = undefined;
		});
	});
});
