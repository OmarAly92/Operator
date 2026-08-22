import { beforeEach, describe, expect, it, vi } from "vitest";

const { postStub } = vi.hoisted(() => ({ postStub: vi.fn() }));

vi.mock("./api-client", () => ({
	apiClient: { POST: postStub },
	apiErrorMessage: (error: unknown) =>
		typeof error === "object" && error !== null && "message" in error
			? String((error as { message: unknown }).message)
			: "Request failed",
}));

import { createTauriBridge } from "./tauri-bridge";

function bridge() {
	return createTauriBridge({ invoke: vi.fn(), listen: vi.fn() });
}

describe("tauri-bridge local folder scans", () => {
	beforeEach(() => {
		postStub.mockReset();
	});

	it("scans an import folder through the LAN-blocked dev route", async () => {
		postStub.mockResolvedValue({
			data: {
				path: "/repos",
				repos: [
					{
						name: "app",
						path: "/repos/app",
						relativePath: "app",
						branch: "main",
						remote: "https://example.com/app.git",
						hasRemote: true,
						status: "ok",
					},
				],
				setupWarning: "Selected folder is inside an existing Git repository at /repos.",
			},
		});

		const result = await bridge().app.scanImportFolder({ path: "/repos", mode: "workspace" });

		expect(postStub).toHaveBeenCalledWith("/api/v1/dev/import-scan", {
			body: { path: "/repos", mode: "workspace" },
		});
		expect(result.path).toBe("/repos");
		expect(result.setupWarning).toContain("existing Git repository");
		expect(result.repos[0]).toMatchObject({ name: "app", status: "ok", hasRemote: true });
	});

	it("omits setupWarning when the daemon reports none", async () => {
		postStub.mockResolvedValue({ data: { path: "/repos", repos: [] } });

		const result = await bridge().app.scanImportFolder({ path: "/repos", mode: "project" });

		expect("setupWarning" in result).toBe(false);
		expect(result.repos).toEqual([]);
	});

	it("surfaces scan failures as thrown errors", async () => {
		postStub.mockResolvedValue({ data: undefined, error: { message: "readdir failed" } });

		await expect(
			bridge().app.scanImportFolder({ path: "/repos", mode: "workspace" }),
		).rejects.toThrow("readdir failed");
	});

	it("checks the ancestor repository through its dev route", async () => {
		postStub.mockResolvedValue({ data: { setupWarning: "inside an existing repository" } });

		const warning = await bridge().app.checkAncestorRepo("/parent/inner");

		expect(postStub).toHaveBeenCalledWith("/api/v1/dev/ancestor-repository", {
			body: { path: "/parent/inner" },
		});
		expect(warning).toBe("inside an existing repository");
	});

	it("returns undefined when no ancestor repository exists", async () => {
		postStub.mockResolvedValue({ data: {} });

		expect(await bridge().app.checkAncestorRepo("/plain")).toBeUndefined();
	});
});
