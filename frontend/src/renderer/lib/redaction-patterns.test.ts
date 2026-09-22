import { beforeEach, describe, expect, it, vi } from "vitest";

const { apiGetMock } = vi.hoisted(() => ({ apiGetMock: vi.fn() }));

vi.mock("./api-client", () => ({
	apiClient: { GET: apiGetMock },
	apiErrorMessage: () => "Request failed",
}));

import { fetchRedactionPatterns, redactionPatternsQueryKey } from "./redaction-patterns";

describe("redaction patterns", () => {
	beforeEach(() => apiGetMock.mockReset());

	it("maps the daemon's shapes to source/flags pairs", async () => {
		apiGetMock.mockResolvedValue({
			data: {
				patterns: [
					{ source: "\\bAKIA[0-9A-Z]{16}\\b", flags: "i" },
					{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b", flags: "" },
				],
			},
		});

		await expect(fetchRedactionPatterns()).resolves.toEqual([
			{ source: "\\bAKIA[0-9A-Z]{16}\\b", flags: "i" },
			{ source: "\\bgh[pousr]_[A-Za-z0-9]{20,}\\b", flags: "" },
		]);
		expect(apiGetMock).toHaveBeenCalledWith("/api/v1/redaction/patterns", {});
		expect(redactionPatternsQueryKey).toEqual(["redaction", "patterns"]);
	});

	it("throws when the daemon answers with an error", async () => {
		apiGetMock.mockResolvedValue({ error: { message: "boom" } });
		await expect(fetchRedactionPatterns()).rejects.toThrow("Request failed");
	});
});
