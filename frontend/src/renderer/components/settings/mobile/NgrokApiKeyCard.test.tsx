import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { mobileStatus, ngrokStatus, ngrokAccount, put, del } = vi.hoisted(() => ({
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
		credentials: [], endpoints: [], error: "", reservedDomains: [], sessions: [], valid: false,
	},
	put: vi.fn(async () => ({ data: {}, error: undefined })),
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
		PUT: put,
		DELETE: del,
	},
	apiErrorMessage: () => "failed",
}));

import { useMobileBridge } from "./useMobileBridge";
import { useNgrok } from "./useNgrok";
import { NgrokApiKeyCard } from "./NgrokApiKeyCard";

const baseAccount = { credentials: [], endpoints: [], error: "", reservedDomains: [], sessions: [], valid: false };

function renderCard(overrides: { apiKey: { present: boolean } }) {
	Object.assign(ngrokStatus, { apiKey: overrides.apiKey });
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	function Harness() {
		const bridge = useMobileBridge(true);
		const ngrok = useNgrok(true);
		return <NgrokApiKeyCard bridge={bridge} ngrok={ngrok} />;
	}
	return render(
		<QueryClientProvider client={client}>
			<Harness />
		</QueryClientProvider>,
	);
}

describe("NgrokApiKeyCard", () => {
	beforeEach(() => {
		Object.assign(ngrokAccount, baseAccount);
		put.mockClear();
		del.mockClear();
	});

	test("no key: Add key opens the dialog and PUTs", async () => {
		renderCard({ apiKey: { present: false } });
		await userEvent.click(await screen.findByRole("button", { name: "Add key" }));
		await userEvent.type(screen.getByLabelText("ngrok API key"), "sekret");
		await userEvent.click(screen.getByRole("button", { name: "Save" }));
		await waitFor(() =>
			expect(put).toHaveBeenCalledWith("/api/v1/mobile/tunnel/ngrok/api-key", { body: { key: "sekret" } }),
		);
	});

	test("invalid key: shows ngrok's error and Replace", async () => {
		Object.assign(ngrokAccount, { valid: false, error: "tunnel: ngrok rejected the API key" });
		renderCard({ apiKey: { present: true } });
		expect(await screen.findByText(/rejected the API key/)).toHaveClass("text-error");
		expect(screen.getByRole("button", { name: "Replace" })).toBeInTheDocument();
	});

	test("valid key: lists domains, credentials, sessions, endpoints and sets the domain", async () => {
		Object.assign(ngrokAccount, {
			valid: true,
			error: "",
			credentials: [{ id: "cr_1", description: "Operator on mac", createdAt: "2026-09-01T00:00:00Z", isOperator: true }],
			sessions: [
				{
					id: "ts_1",
					region: "eu",
					ip: "1.2.3.4",
					agentVersion: "3.39.6",
					os: "darwin",
					startedAt: "2026-09-19T17:00:00Z",
					isThisMachine: true,
				},
			],
			endpoints: [{ id: "ep_1", publicUrl: "https://a.ngrok.app", proto: "https", createdAt: "" }],
			reservedDomains: [{ id: "rd_1", domain: "phone.example.ngrok.app" }],
		});
		renderCard({ apiKey: { present: true } });
		expect(await screen.findByText("Operator on mac")).toBeInTheDocument();
		expect(screen.getByText("This machine")).toBeInTheDocument();
		expect(screen.getByText("https://a.ngrok.app")).toBeInTheDocument();

		const user = userEvent.setup({ pointerEventsCheck: 0 });
		await user.click(screen.getByRole("combobox", { name: "Stable domain" }));
		await user.click(await screen.findByRole("option", { name: "phone.example.ngrok.app" }));
		await waitFor(() =>
			expect(put).toHaveBeenCalledWith("/api/v1/mobile/tunnel/ngrok/domain", { body: { domain: "phone.example.ngrok.app" } }),
		);
	});

	test("revoke calls DELETE with the id", async () => {
		Object.assign(ngrokAccount, {
			valid: true,
			error: "",
			credentials: [{ id: "cr_1", description: "Operator on mac", createdAt: "2026-09-01T00:00:00Z", isOperator: true }],
			sessions: [],
			endpoints: [],
			reservedDomains: [],
		});
		renderCard({ apiKey: { present: true } });
		await userEvent.click(await screen.findByRole("button", { name: "Revoke" }));
		await waitFor(() =>
			expect(del).toHaveBeenCalledWith("/api/v1/mobile/tunnel/ngrok/account/credential/{id}", {
				params: { path: { id: "cr_1" } },
			}),
		);
	});
});
