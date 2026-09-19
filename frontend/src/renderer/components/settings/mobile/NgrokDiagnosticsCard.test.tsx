import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

import { NgrokLogPanel } from "./NgrokLogPanel";

function mockScrollMetrics(node: HTMLElement, metrics: { scrollTop: number; scrollHeight: number; clientHeight: number }) {
	Object.defineProperty(node, "scrollTop", { value: metrics.scrollTop, writable: true, configurable: true });
	Object.defineProperty(node, "scrollHeight", { value: metrics.scrollHeight, configurable: true });
	Object.defineProperty(node, "clientHeight", { value: metrics.clientHeight, configurable: true });
}

const { ngrokStatus, post } = vi.hoisted(() => ({
	ngrokStatus: {
		credential: { present: false, source: "", systemConfigPath: "", suffix: "" },
		agent: { binaryPath: "", source: "", version: "", updateAvailable: false },
		session: { status: "", region: "", latency: "", publicUrl: "", connections: 0, httpRequests: 0 },
		domain: "", apiKey: { present: false }, logs: [] as unknown[],
	},
	post: vi.fn(async () => ({ data: {}, error: undefined })),
}));

vi.mock("../../../lib/api-client", () => ({
	apiClient: {
		GET: async (path: string) => {
			if (path === "/api/v1/mobile/tunnel/ngrok") return { data: ngrokStatus, error: undefined };
			if (path === "/api/v1/mobile/tunnel/ngrok/account") return { data: undefined, error: undefined };
			return { data: undefined, error: undefined };
		},
		POST: post,
		PUT: vi.fn(async () => ({ data: {}, error: undefined })),
		DELETE: vi.fn(async () => ({ data: {}, error: undefined })),
	},
	apiErrorMessage: () => "failed",
}));

import { useNgrok } from "./useNgrok";
import { NgrokDiagnosticsCard } from "./NgrokDiagnosticsCard";

function renderCard({ logs }: { logs: unknown[] }) {
	Object.assign(ngrokStatus, { logs });
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	function Harness() {
		const ngrok = useNgrok(true);
		return <NgrokDiagnosticsCard ngrok={ngrok} />;
	}
	return render(
		<QueryClientProvider client={client}>
			<Harness />
		</QueryClientProvider>,
	);
}

describe("NgrokDiagnosticsCard", () => {
	beforeEach(() => {
		post.mockClear();
	});

	test("runs diagnostics and renders each check with the summary", async () => {
		post.mockResolvedValueOnce({
			data: {
				summary: "Plain HTTP is being intercepted on this network (redirected to megaplusredirection.tedata.net).",
				checks: [
					{ name: "Binary", ok: true, detail: "/opt/homebrew/bin/ngrok (path): ngrok version 3.39.6" },
					{ name: "CRL over HTTP", ok: false, detail: "Plain HTTP is being intercepted on this network (redirected to megaplusredirection.tedata.net)." },
				],
			},
			error: undefined,
		});
		renderCard({ logs: [] });
		await userEvent.click(await screen.findByRole("button", { name: "Run diagnostics" }));
		expect(await screen.findByText(/intercepted on this network/)).toBeInTheDocument();
		expect(screen.getByText("CRL over HTTP").closest("li")).toHaveAttribute("data-ok", "false");
		expect(screen.getByText("Binary").closest("li")).toHaveAttribute("data-ok", "true");
	});

	test("log panel highlights errors, never shows a token, and copies the joined lines", async () => {
		const writeText = vi.fn();
		Object.assign(navigator, { clipboard: { writeText } });
		renderCard({
			logs: [
				{ time: "2026-09-19T20:05:59+03:00", level: "info", message: "open config file" },
				{ time: "2026-09-19T20:06:00+03:00", level: "eror", message: "failed to reconnect session: [redacted]" },
			],
		});
		const err = await screen.findByText(/failed to reconnect session/);
		expect(err.closest("[data-level]")).toHaveAttribute("data-level", "eror");
		expect(err).toHaveClass("text-error");
		expect(screen.queryByText(/2mintedtoken|sekret/)).not.toBeInTheDocument();
		await userEvent.click(screen.getByRole("button", { name: "Copy log" }));
		expect(writeText).toHaveBeenCalledWith(expect.stringContaining("open config file\n"));
	});
});

describe("NgrokLogPanel auto-scroll", () => {
	test("scrolls to the bottom when a new line arrives", () => {
		const { getByTestId, rerender } = render(
			<NgrokLogPanel lines={[{ time: "", level: "info", message: "a" }]} />,
		);
		const node = getByTestId("ngrok-log-scroll");
		mockScrollMetrics(node, { scrollTop: 0, scrollHeight: 100, clientHeight: 50 });
		rerender(
			<NgrokLogPanel
				lines={[
					{ time: "", level: "info", message: "a" },
					{ time: "", level: "info", message: "b" },
				]}
			/>,
		);
		expect(node.scrollTop).toBe(100);
	});

	test("stays put once the user has scrolled up", () => {
		const { getByTestId, rerender } = render(
			<NgrokLogPanel lines={[{ time: "", level: "info", message: "a" }]} />,
		);
		const node = getByTestId("ngrok-log-scroll");
		mockScrollMetrics(node, { scrollTop: 0, scrollHeight: 100, clientHeight: 50 });
		fireEvent.scroll(node);
		rerender(
			<NgrokLogPanel
				lines={[
					{ time: "", level: "info", message: "a" },
					{ time: "", level: "info", message: "b" },
				]}
			/>,
		);
		expect(node.scrollTop).toBe(0);
	});
});
