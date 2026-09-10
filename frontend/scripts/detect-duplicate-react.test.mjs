import { strict as assert } from "node:assert";
import test from "node:test";
import { duplicateReactRoots } from "./detect-duplicate-react.mjs";

test("a single react install is not a duplicate", () => {
	assert.deepEqual(
		duplicateReactRoots([
			"/repo/frontend/node_modules/react/index.js",
			"/repo/frontend/node_modules/react/cjs/react.production.js",
			"/repo/frontend/src/renderer/main.tsx",
		]),
		[],
	);
});

test("react reached through a symlinked workspace package is reported", () => {
	assert.deepEqual(
		duplicateReactRoots([
			"/repo/frontend/node_modules/react/index.js",
			"/repo/packages/terminal/node_modules/react/index.js",
		]),
		["/repo/frontend/node_modules/react", "/repo/packages/terminal/node_modules/react"],
	);
});

test("react-dom duplicates are reported too", () => {
	assert.deepEqual(
		duplicateReactRoots([
			"/repo/frontend/node_modules/react-dom/client.js",
			"/repo/packages/terminal/node_modules/react-dom/client.js",
		]),
		["/repo/frontend/node_modules/react-dom", "/repo/packages/terminal/node_modules/react-dom"],
	);
});

test("packages whose name merely starts with react are not confused for react", () => {
	assert.deepEqual(
		duplicateReactRoots([
			"/repo/frontend/node_modules/react-refresh/runtime.js",
			"/repo/packages/terminal/node_modules/react-router/index.js",
		]),
		[],
	);
});

test("windows-style separators resolve to the same package root", () => {
	assert.deepEqual(duplicateReactRoots(["C:\\repo\\frontend\\node_modules\\react\\index.js"]), []);
});
