import { describe, expect, it, vi } from "vitest";
import { createOrderedReporter } from "./reporter";

describe("terminal benchmark reporter", () => {
	it("waits for each acknowledgement request before sending the next", async () => {
		let releaseFirst: (() => void) | undefined;
		const fetchImpl = vi.fn()
			.mockImplementationOnce(() => new Promise<void>((resolve) => { releaseFirst = resolve; }))
			.mockResolvedValue(undefined);
		const report = createOrderedReporter("http://127.0.0.1:4317/report", fetchImpl);
		const first = report({ name: "workload-start", timestamp: 1 });
		const second = report({ name: "scroll", timestamp: 2 });
		await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(1));
		releaseFirst?.();
		await Promise.all([first, second]);
		expect(fetchImpl).toHaveBeenCalledTimes(2);
		expect(fetchImpl.mock.calls.map((call) => JSON.parse(call[1].body))).toEqual([
			{ name: "workload-start", timestamp: 1 },
			{ name: "scroll", timestamp: 2 },
		]);
	});
});
