import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { describe, expect, test, vi } from "vitest";

const { mobileStatus } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true, host: "192.168.1.20", port: 3011, password: "pw", warning: "",
		tunnel: { state: "off", provider: "ngrok", url: "", error: "", restarts: 0, needsAuthtoken: false, hasAuthtoken: false },
	},
}));
vi.mock("../../../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../../../lib/api-client", () => ({
	apiClient: { GET: async () => ({ data: mobileStatus, error: undefined }), POST: vi.fn(), PUT: vi.fn(), DELETE: vi.fn() },
	apiErrorMessage: () => "failed",
}));

import { MobileSettingsSection } from "./MobileSettingsSection";

describe("MobileSettingsSection", () => {
	test("renders connection and public access inside the Mobile tab", async () => {
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		render(
			<QueryClientProvider client={client}>
				<MobileSettingsSection />
			</QueryClientProvider>,
		);
		expect(await screen.findByRole("switch", { name: "Enable mobile" })).toBeInTheDocument();
		expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeInTheDocument();
		expect(screen.getByText("ngrok")).toBeInTheDocument();
	});
});
