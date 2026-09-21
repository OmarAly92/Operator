import { describe, expect, it } from "vitest";
import { createProjectConfig } from "../routes/_shell";

describe("createProjectConfig", () => {
	it("persists the selected worker agent without tracker intake by default", () => {
		expect(
			createProjectConfig({
				workerAgent: "codex",
			}),
		).toEqual({
			agent: "codex",
		});
	});

	it("preserves tracker intake alongside the selected agent default", () => {
		expect(
			createProjectConfig({
				workerAgent: "cursor",
				trackerIntake: { enabled: true, provider: "github", assignee: "octocat" },
			}),
		).toEqual({
			agent: "cursor",
			trackerIntake: { enabled: true, provider: "github", assignee: "octocat" },
		});
	});
});
