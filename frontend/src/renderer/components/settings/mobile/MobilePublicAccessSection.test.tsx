import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { describe, expect, test, vi } from "vitest";

const { mobileStatus } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true, host: "192.168.1.20", port: 3011, password: "pw", warning: "",
		tunnel: { state: "live", provider: "cloudflared", url: "https://x.trycloudflare.com", error: "ngrok could not fetch its certificate revocation list", restarts: 0, needsAuthtoken: false, hasAuthtoken: true, lastProvider: "ngrok", fallbackReason: "ngrok could not fetch its certificate revocation list" },
	},
}));
vi.mock("../../../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../../../lib/api-client", () => ({
	apiClient: { GET: async () => ({ data: mobileStatus, error: undefined }), POST: vi.fn(), PUT: vi.fn(), DELETE: vi.fn() },
	apiErrorMessage: () => "failed",
}));

import { useMobileBridge } from "./useMobileBridge";
import { MobilePublicAccessSection } from "./MobilePublicAccessSection";

function Harness() {
	const bridge = useMobileBridge(true);
	return <MobilePublicAccessSection bridge={bridge} />;
}

describe("MobilePublicAccessSection", () => {
	test("explains a fallback while live on cloudflared", async () => {
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		render(<QueryClientProvider client={client}><Harness /></QueryClientProvider>);
		expect(await screen.findByText(/Using cloudflared/)).toBeInTheDocument();
		expect(screen.getByText(/certificate revocation list/)).toBeInTheDocument();
		expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeChecked();
	});
});
