import { describe, expect, it } from "vitest";
import { buildContentSecurityPolicy } from "./csp";

function directive(policy: string, name: string): string {
	const found = policy
		.split(";")
		.map((part) => part.trim())
		.find((part) => part === name || part.startsWith(`${name} `));
	expect(found, `missing ${name} directive`).toBeDefined();
	return found as string;
}

describe("buildContentSecurityPolicy", () => {
	it("allows WebAssembly compilation for the terminal core", () => {
		expect(directive(buildContentSecurityPolicy([]), "script-src")).toContain("'wasm-unsafe-eval'");
	});

	it("does not widen script execution to full unsafe-eval", () => {
		expect(directive(buildContentSecurityPolicy([]), "script-src")).not.toContain("'unsafe-eval'");
	});

	it("keeps the daemon loopback origins in connect-src", () => {
		const connect = directive(buildContentSecurityPolicy([]), "connect-src");
		expect(connect).toContain("http://127.0.0.1:*");
		expect(connect).toContain("ws://127.0.0.1:*");
	});

	it("appends the PostHog origins to connect-src", () => {
		const connect = directive(
			buildContentSecurityPolicy(["https://eu.posthog.com", "https://eu-assets.posthog.com"]),
			"connect-src",
		);
		expect(connect).toContain("https://eu.posthog.com");
		expect(connect).toContain("https://eu-assets.posthog.com");
	});
});
