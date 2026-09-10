// defineConfig comes from vitest/config (a superset of vite's) so the `test`
// block typechecks; vitest itself must be pointed at this file explicitly
// (package.json test script) because it only auto-discovers vite.config.*.
import { defineConfig } from "vitest/config";
import type { Plugin } from "vite";
import { fileURLToPath, URL } from "node:url";
import { TanStackRouterVite } from "@tanstack/router-plugin/vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { DEFAULT_POSTHOG_HOST } from "./src/shared/posthog-config";
import { buildContentSecurityPolicy } from "./src/shared/csp";
// @ts-expect-error -- build tooling ships as plain .mjs with no type declarations.
import { assertSingleReact } from "./scripts/detect-duplicate-react.mjs";

const POSTHOG_ORIGINS = (() => {
	const configured = process.env.VITE_OPERATOR_POSTHOG_HOST?.trim() || DEFAULT_POSTHOG_HOST;
	if (!configured) return [];
	let url: URL;
	try {
		url = new URL(configured);
	} catch {
		return [];
	}
	// posthog-js serves capture from api_host but fetches remote config from a
	// sibling "-assets" host it derives from the same name, so a CSP built only
	// from api_host blocks that request and logs a console error on every launch
	// of a packaged build. Capture is unaffected (it uses api_host), and Operator
	// ignores what remote config offers, since replay, flags, and surveys are all
	// disabled in the client. Allowing the origin only silences the error; the
	// client settings still win over anything the server would say.
	//
	// The asset_host option deliberately does not cover this: per its own docs it
	// "only applies to /static/* asset paths; dynamic assets like remote config
	// continue to use the regular asset host derived from api_host".
	// Scoped to PostHog Cloud, matching what posthog-js itself does: it only
	// rewrites to an "-assets" sibling for *.posthog.com. A self-hosted instance
	// or a loopback capture endpoint serves everything from one origin, and
	// deriving there would emit a nonsense entry (127.0.0.1 would become
	// "127-assets.0.0.1").
	const origins = [url.origin];
	if (/\.posthog\.com$/i.test(url.hostname)) {
		const assetsHost = url.hostname.replace(/^([^.]+)\./, "$1-assets.");
		if (assetsHost !== url.hostname) origins.push(`${url.protocol}//${assetsHost}`);
	}
	return origins;
})();

// The policy itself lives in src/shared/csp.ts so it can be unit tested;
// it is injected at build time rather than written into index.html because
// the dev server needs inline scripts (react-refresh preamble) that a static
// meta tag would block.
const CONTENT_SECURITY_POLICY = buildContentSecurityPolicy(POSTHOG_ORIGINS);

const injectCspMeta: Plugin = {
	name: "inject-csp-meta",
	apply: "build",
	transformIndexHtml() {
		return [
			{
				tag: "meta",
				attrs: { "http-equiv": "Content-Security-Policy", content: CONTENT_SECURITY_POLICY },
				injectTo: "head-prepend",
			},
		];
	},
};

const DEV_PROXY_ORIGIN = "tauri://localhost";

export default defineConfig(({ command }) => ({
	// "@/" → the renderer root (src/renderer), the shadcn/ui import convention.
	resolve: {
		alias: {
			"@": fileURLToPath(new URL("./src/renderer", import.meta.url)),
		},
		// The @operator/terminal-* packages are symlinked file: deps that carry
		// their own react devDependency, so a bare "react" inside them resolves
		// to packages/terminal/node_modules/react. Dev survives it -- the dep
		// optimizer flattens bare specifiers -- but the build resolves per
		// importer and emits a SECOND React whose hook dispatcher is always
		// null, which is "null is not an object (evaluating 'c.H.useRef')" the
		// moment a terminal pane mounts.
		//
		// Build only: under vitest the tracked src/landing preview app resolves
		// react from its OWN nested node_modules, and collapsing that onto the
		// frontend copy splits it from the @testing-library/react beside it --
		// the same null dispatcher, in the other direction.
		dedupe: command === "build" ? ["react", "react-dom"] : [],
	},
	// Dev proxy for VITE_RENDERER_PREVIEW=1 browser preview — forwards /api and
	// /mux to the daemon so the renderer can be tested against a running daemon
	// from a plain browser without the desktop shell.
	server: {
		fs: {
			allow: [fileURLToPath(new URL("..", import.meta.url))],
		},
		proxy: {
			"/api": {
				target: process.env.OPERATOR_DEV_API_TARGET ?? "http://127.0.0.1:3001",
				changeOrigin: false,
				headers: { origin: DEV_PROXY_ORIGIN },
			},
			"/mux": {
				target: process.env.OPERATOR_DEV_API_TARGET ?? "http://127.0.0.1:3001",
				changeOrigin: false,
				ws: true,
				headers: { origin: DEV_PROXY_ORIGIN },
			},
			"/readyz": {
				target: process.env.OPERATOR_DEV_API_TARGET ?? "http://127.0.0.1:3001",
				changeOrigin: false,
			},
		},
	},
	plugins: [
		TanStackRouterVite({
			routesDirectory: "./src/renderer/routes",
			generatedRouteTree: "./src/renderer/routeTree.gen.ts",
			target: "react",
			autoCodeSplitting: true,
		}),
		react(),
		tailwindcss(),
		injectCspMeta,
		assertSingleReact(),
	],
	test: {
		environment: "jsdom",
		testTimeout: 20_000,
		// Anchor node_modules at any depth: a bare "node_modules/**" replaces
		// vitest's default "**/node_modules/**" and only matches the root, so the
		// tracked src/landing preview app's nested node_modules would otherwise
		// have its vendored third-party test suites collected and run.
		exclude: [
			"**/node_modules/**",
			"dist/**",
			"e2e/**",
			"scripts/agent-browser-phase0.test.mjs",
			"scripts/audit-tauri-state.test.mjs",
			"scripts/benchmark-result.test.mjs",
			"scripts/check-parity-ledger.test.mjs",
			"scripts/e2e-mac-update.test.mjs",
			"scripts/detect-duplicate-react.test.mjs",
			"scripts/e2e-tauri-build-contract.test.mjs",
			"scripts/feed.test.mjs",
			"scripts/heap-summary.test.mjs",
			"scripts/no-electron.test.mjs",
			"scripts/phase0-aggregate.test.mjs",
			"scripts/phase0-decision.test.mjs",
			"scripts/phase0-legacy-update.test.mjs",
			"scripts/phase0-platform-summary.test.mjs",
			"scripts/phase0-updater-signing.test.mjs",
			"scripts/route-bundle-report.test.mjs",
			"scripts/tauri-feed.test.mjs",
		],
		globals: true,
		setupFiles: "./src/renderer/test/setup.ts",
	},
}));
