import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { components } from "../../api/schema";
import type { TerminalTarget } from "../types/terminal";
import { shellTerminalsQueryKey } from "./useShellTerminals";
import { useShellTerminalBlocks } from "./useShellTerminalBlocks";

const { getMock } = vi.hoisted(() => ({ getMock: vi.fn() }));

vi.mock("../lib/api-client", () => ({
	apiClient: { GET: getMock },
	apiErrorMessage: (error: unknown, fallback = "Request failed") => {
		if (error instanceof Error) return error.message;
		if (typeof error === "object" && error !== null && "message" in error) {
			return String((error as { message: unknown }).message);
		}
		return fallback;
	},
	getApiBaseUrl: () => "http://127.0.0.1:3001",
	hasTrustedApiBaseUrl: () => false,
}));

type BlockDto = components["schemas"]["TerminalBlockView"];

function blockDto(over: Partial<BlockDto> = {}): BlockDto {
	return {
		terminalId: "shellterm-1",
		sourceId: "src",
		command: "",
		cwd: "",
		gitBranch: "",
		exitCode: null,
		rawOutput: "",
		startedAt: "2026-08-31T00:00:00Z",
		finishedAt: "2026-08-31T00:00:01Z",
		createdAt: "2026-08-31T00:00:01Z",
		shellKind: "zsh",
		shellVersion: "5.9",
		truncatedLines: 0,
		truncatedBytes: 0,
		captureEpoch: "epoch-1",
		startOffset: 0,
		endOffset: 0,
		...over,
	};
}

function shellTarget(): TerminalTarget {
	return { kind: "shell", handleId: "shell-1", generation: "g1", title: "scratch" };
}

function makeWrapper(client = new QueryClient({ defaultOptions: { queries: { retry: false } } })) {
	return { client, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> };
}

beforeEach(() => {
	getMock.mockReset();
	getMock.mockResolvedValue({ data: [], error: undefined });
});

describe("useShellTerminalBlocks", () => {
	it("does not fetch for a non-shell target", async () => {
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks({ kind: "worker" }), { wrapper });
		await Promise.resolve();
		expect(getMock).not.toHaveBeenCalled();
		expect(result.current.blocks).toEqual([]);
		expect(result.current.isLoading).toBe(false);
	});

	it("fetches the handle's history and returns it oldest-to-newest", async () => {
		getMock.mockResolvedValue({
			data: [blockDto({ sourceId: "old" }), blockDto({ sourceId: "new" })],
			error: undefined,
		});
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });

		await waitFor(() => expect(result.current.blocks).toHaveLength(2));
		expect(result.current.blocks.map((b) => b.sourceId)).toEqual(["old", "new"]);
		const call = getMock.mock.calls[0];
		expect(call[0]).toBe("/api/v1/shell-terminals/{handleId}/blocks");
		expect(call[1].params.path.handleId).toBe("shell-1");
	});

	it("decodes base64 rawOutput to exact bytes, including 0x00/0x80/0xfe/0xff and a CSI SGR run", async () => {
		const raw = Uint8Array.from([
			0x00, 0x01, 0x80, 0xfe, 0xff, 0x1b, 0x5b, 0x33, 0x31, 0x6d, 0x41, 0x1b, 0x5b, 0x30, 0x6d,
		]);
		const b64 = btoa(String.fromCharCode(...raw));
		getMock.mockResolvedValue({ data: [blockDto({ rawOutput: b64 })], error: undefined });
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });

		await waitFor(() => expect(result.current.blocks).toHaveLength(1));
		expect(Array.from(result.current.blocks[0].rawOutput)).toEqual(Array.from(raw));
	});

	it("surfaces a fetch error without throwing and keeps blocks empty", async () => {
		getMock.mockResolvedValue({ data: undefined, error: { message: "boom" } });
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });

		await waitFor(() => expect(result.current.error).toBeDefined(), { timeout: 5000 });
		expect(result.current.error).toContain("boom");
		expect(result.current.blocks).toEqual([]);
	});

	it("does not retry a failed history request before enabling the live terminal", async () => {
		getMock.mockResolvedValue({ data: undefined, error: { message: "offline" } });
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });

		await waitFor(() => expect(result.current.error).toContain("offline"), { timeout: 5000 });
		expect(getMock).toHaveBeenCalledTimes(1);
	});

	it("reports durableBlocks=false from the cached shell-terminal list", async () => {
		const { client, wrapper } = makeWrapper();
		client.setQueryData(shellTerminalsQueryKey, [
			{ handleId: "shell-1", workingDir: "/x", title: "scratch", createdAt: "2026-08-31T00:00:00Z", durableBlocks: false },
		]);
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });

		await waitFor(() => expect(result.current.isLoading).toBe(false));
		expect(result.current.durableBlocks).toBe(false);
	});

	it("reacts when the shell-terminal capability changes", async () => {
		const { client, wrapper } = makeWrapper();
		client.setQueryData(shellTerminalsQueryKey, [
			{ handleId: "shell-1", workingDir: "/x", title: "scratch", createdAt: "2026-08-31T00:00:00Z", durableBlocks: true },
		]);
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });
		await waitFor(() => expect(result.current.isLoading).toBe(false));
		expect(result.current.durableBlocks).toBe(true);

		act(() => {
			client.setQueryData(shellTerminalsQueryKey, [
				{ handleId: "shell-1", workingDir: "/x", title: "scratch", createdAt: "2026-08-31T00:00:00Z", durableBlocks: false },
			]);
		});

		await waitFor(() => expect(result.current.durableBlocks).toBe(false));
	});

	it("defaults durableBlocks to true when the shell is not in the cached list", async () => {
		const { wrapper } = makeWrapper();
		const { result } = renderHook(() => useShellTerminalBlocks(shellTarget()), { wrapper });
		await waitFor(() => expect(result.current.isLoading).toBe(false));
		expect(result.current.durableBlocks).toBe(true);
	});
});
