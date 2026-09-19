import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, test, vi } from "vitest";

const { mobileStatus, ngrokStatus, ngrokAccount, del } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true, host: "192.168.1.20", port: 3011, password: "pw", warning: "",
		tunnel: { state: "off", provider: "ngrok", url: "", error: "", restarts: 0, needsAuthtoken: false, hasAuthtoken: false },
	},
	ngrokStatus: {
		credential: { present: false, source: "", systemConfigPath: "", suffix: "" },
		agent: { binaryPath: "", source: "", version: "", updateAvailable: false },
		session: { status: "", region: "", latency: "", publicUrl: "", connections: 0, httpRequests: 0 },
		domain: "", apiKey: { present: false }, logs: [],
	},
	ngrokAccount: {
		credentials: [], endpoints: [], error: "", reservedDomains: [], sessions: [], valid: true,
	},
	del: vi.fn(async () => ({ data: {}, error: undefined })),
}));

vi.mock("../../../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../../../lib/bridge", () => ({ operatorBridge: { app: { openExternal: vi.fn() } } }));
vi.mock("../../../lib/api-client", () => ({
	apiClient: {
		GET: async (path: string) => {
			if (path === "/api/v1/mobile/status") return { data: mobileStatus, error: undefined };
			if (path === "/api/v1/mobile/tunnel/ngrok") return { data: ngrokStatus, error: undefined };
			if (path === "/api/v1/mobile/tunnel/ngrok/account") return { data: ngrokAccount, error: undefined };
			return { data: undefined, error: undefined };
		},
		POST: vi.fn(async () => ({ data: {}, error: undefined })),
		PUT: vi.fn(async () => ({ data: {}, error: undefined })),
		DELETE: del,
	},
	apiErrorMessage: () => "failed",
}));

import { useMobileBridge } from "./useMobileBridge";
import { useNgrok } from "./useNgrok";
import { NgrokSection } from "./NgrokSection";

function renderSection() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	function Harness() {
		const bridge = useMobileBridge(true);
		const ngrok = useNgrok(true);
		return <NgrokSection bridge={bridge} ngrok={ngrok} />;
	}
	return render(
		<QueryClientProvider client={client}>
			<Harness />
		</QueryClientProvider>,
	);
}

const baseNgrok = {
	credential: { present: false, source: "", systemConfigPath: "/Users/me/Library/Application Support/ngrok/ngrok.yml", suffix: "" },
	agent: { binaryPath: "/opt/homebrew/bin/ngrok", source: "path", version: "3.39.6", updateAvailable: true },
	session: { status: "", region: "", latency: "", publicUrl: "", connections: 0, httpRequests: 0 },
	domain: "", apiKey: { present: false }, logs: [],
};

describe("NgrokSection", () => {
	test("no credential: offers Log in and hides Remove", async () => {
		Object.assign(ngrokStatus, baseNgrok);
		renderSection();
		expect(await screen.findByText("Not logged in")).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Log in" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Remove" })).not.toBeInTheDocument();
	});

	test("system credential: names the file and offers Replace only", async () => {
		Object.assign(ngrokStatus, baseNgrok, { credential: { present: true, source: "system", systemConfigPath: "/x/ngrok.yml", suffix: "" } });
		renderSection();
		expect(await screen.findByText(/Using your system ngrok login/)).toBeInTheDocument();
		expect(screen.getByText(/\/x\/ngrok\.yml/)).toBeInTheDocument();
		expect(screen.getByRole("button", { name: "Replace token" })).toBeInTheDocument();
		expect(screen.queryByRole("button", { name: "Remove" })).not.toBeInTheDocument();
	});

	test("operator credential: shows the suffix and Remove calls DELETE", async () => {
		Object.assign(ngrokStatus, baseNgrok, { credential: { present: true, source: "operator", systemConfigPath: "", suffix: "wxyz" } });
		renderSection();
		expect(await screen.findByText(/…wxyz/)).toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Remove" }));
		await userEvent.click(await screen.findByRole("button", { name: "Remove token" }));
		await waitFor(() => expect(del).toHaveBeenCalledWith("/api/v1/mobile/tunnel/authtoken"));
	});

	test("session card shows agent facts and live session", async () => {
		Object.assign(ngrokStatus, baseNgrok, { session: { status: "online", region: "eu", latency: "62ms", publicUrl: "https://a.ngrok.app", connections: 3, httpRequests: 12 } });
		renderSection();
		expect(await screen.findByText("Online")).toBeInTheDocument();
		expect(screen.getByText("eu · 62ms")).toBeInTheDocument();
		expect(screen.getByText("https://a.ngrok.app")).toBeInTheDocument();
		expect(screen.getByText("/opt/homebrew/bin/ngrok")).toBeInTheDocument();
		expect(screen.getByText("Homebrew / PATH")).toBeInTheDocument();
		expect(screen.getByText("Update available")).toBeInTheDocument();
	});
});
