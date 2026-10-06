import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { shellTerminalsQueryKey, useOpenShellTerminal, useShellTerminals } from "./useShellTerminals";

const { getMock, postMock } = vi.hoisted(() => ({ getMock: vi.fn(), postMock: vi.fn() }));

vi.mock("../lib/api-client", () => ({
	apiClient: { GET: getMock, POST: postMock },
	hasTrustedApiBaseUrl: () => true,
}));

function wrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
			{children}
		</QueryClientProvider>
	);
}

beforeEach(() => {
	getMock.mockReset();
});

describe("useShellTerminals", () => {
	it("preserves the durableBlocks capability from the daemon", async () => {
		getMock.mockResolvedValue({
			data: {
				shellTerminals: [
					{
						handleId: "shell-1",
						workingDir: "/tmp",
						title: "scratch",
						createdAt: "2026-08-31T00:00:00Z",
						durableBlocks: false,
					},
				],
			},
			error: undefined,
		});

		const { result } = renderHook(() => useShellTerminals(), { wrapper });
		await waitFor(() => expect(result.current.data).toHaveLength(1));
		expect(result.current.data?.[0].durableBlocks).toBe(false);
	});
});

describe("useOpenShellTerminal", () => {
	it("puts the opened terminal in the list at once, so selecting it does not snap back to the first tab", async () => {
		const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
		const existing = { handleId: "shell-1", workingDir: "/tmp", title: "one", createdAt: "2026-09-27T00:00:00Z" };
		client.setQueryData(shellTerminalsQueryKey, [existing]);
		postMock.mockResolvedValue({
			data: { shellTerminal: { handleId: "shell-2", workingDir: "/tmp", title: "two", createdAt: "2026-09-27T00:00:01Z" } },
			error: undefined,
		});
		getMock.mockReturnValue(new Promise(() => {}));
		const { result } = renderHook(() => useOpenShellTerminal(), {
			wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>,
		});
		let listedOnSuccess: string[] = [];
		await result.current.mutateAsync(
			{ projectId: "proj" },
			{ onSuccess: () => { listedOnSuccess = (client.getQueryData<{ handleId: string }[]>(shellTerminalsQueryKey) ?? []).map((s) => s.handleId); } },
		);
		await waitFor(() => expect(listedOnSuccess).toEqual(["shell-1", "shell-2"]));
	});
});
