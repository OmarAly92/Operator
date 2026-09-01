import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { useShellTerminals } from "./useShellTerminals";

const { getMock } = vi.hoisted(() => ({ getMock: vi.fn() }));

vi.mock("../lib/api-client", () => ({
	apiClient: { GET: getMock },
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
