import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test, vi } from "vitest";

const { mobileStatus, disableDeferred } = vi.hoisted(() => {
	const deferred: { resolve: (value: unknown) => void } = { resolve: () => {} };
	return {
		mobileStatus: {
			enabled: true, host: "192.168.1.20", port: 3011, password: "pw", warning: "",
			tunnel: undefined,
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

function Harness() {
	const bridge = useMobileBridge(true);
	return <MobileConnectionSection bridge={bridge} />;
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
});
