import { readFile, readdir } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const allowedOwners = new Set(["tauri", "go", "renderer"]);
const deferredBrowserRecord = "docs/todo/browser-panel-webview.md";

function entryKey(source, member) {
	return `${source}\u0000${member}`;
}

function displayKey(source, member) {
	return `${source}/${member}`;
}

const deferredBrowserEntries = new Set(
	[
		["main", "browser-view-host.ts"],
		["preload.browser", "clear"],
		["preload.browser", "closeTab"],
		["preload.browser", "destroy"],
		["preload.browser", "devtools"],
		["preload.browser", "ensure"],
		["preload.browser", "getTabs"],
		["preload.browser", "goBack"],
		["preload.browser", "goForward"],
		["preload.browser", "nativeCompositionEnabled"],
		["preload.browser", "navigate"],
		["preload.browser", "onAgentActivity"],
		["preload.browser", "onAnnotationCancel"],
		["preload.browser", "onAnnotationSubmit"],
		["preload.browser", "onDevToolsState"],
		["preload.browser", "onNavState"],
		["preload.browser", "onTabsState"],
		["preload.browser", "openTab"],
		["preload.browser", "reload"],
		["preload.browser", "selectTab"],
		["preload.browser", "setAnnotationMode"],
		["preload.browser", "setBounds"],
		["preload.browser", "setOverlayOpen"],
		["preload.browser", "stop"],
		["renderer/components/BrowserTabsRail.tsx", "../../main/browser-view-host"],
		["renderer/hooks/useBrowserView.ts", "../../main/browser-view-host"],
	].map(([source, member]) => entryKey(source, member)),
);

async function filesBelow(directory) {
	const entries = await readdir(directory, { withFileTypes: true });
	const files = [];
	for (const entry of entries) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) files.push(...(await filesBelow(path)));
		if (entry.isFile()) files.push(path);
	}
	return files;
}

function sourceFile(path, sourceText) {
	const scriptKind = path.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
	return ts.createSourceFile(path, sourceText, ts.ScriptTarget.Latest, true, scriptKind);
}

function propertyName(property, path) {
	if (!property.name) throw new Error(`${path} contains an unsupported spread in the preload API`);
	if (ts.isIdentifier(property.name) || ts.isStringLiteral(property.name) || ts.isNumericLiteral(property.name)) return property.name.text;
	throw new Error(`${path} contains a computed preload API member`);
}

function preloadApi(source, path) {
	for (const statement of source.statements) {
		if (!ts.isVariableStatement(statement)) continue;
		for (const declaration of statement.declarationList.declarations) {
			if (!ts.isIdentifier(declaration.name) || declaration.name.text !== "api") continue;
			if (declaration.initializer && ts.isObjectLiteralExpression(declaration.initializer)) return declaration.initializer;
		}
	}
	throw new Error(`${path} must declare const api as an object literal`);
}

function mainModuleSpecifier(statement) {
	if (!ts.isImportDeclaration(statement) && !ts.isExportDeclaration(statement)) return null;
	if (!statement.moduleSpecifier || !ts.isStringLiteral(statement.moduleSpecifier)) return null;
	return statement.moduleSpecifier.text.startsWith("../../main/") ? statement.moduleSpecifier.text : null;
}

async function preloadInventory(rootDir) {
	const path = join(rootDir, "src", "preload.ts");
	const sourceText = await readFile(path, "utf8");
	const inventory = [];
	const api = preloadApi(sourceFile(path, sourceText), path);
	for (const namespace of api.properties) {
		const namespaceName = propertyName(namespace, path);
		if (!ts.isPropertyAssignment(namespace) || !ts.isObjectLiteralExpression(namespace.initializer)) {
			throw new Error(`${path} preload namespace ${namespaceName} must be an object literal`);
		}
		for (const member of namespace.initializer.properties) {
			inventory.push({ source: `preload.${namespaceName}`, member: propertyName(member, path) });
		}
	}
	return inventory;
}

async function rendererImportInventory(rootDir) {
	const rendererDir = join(rootDir, "src", "renderer");
	const files = (await filesBelow(rendererDir)).filter((path) => /\.[cm]?[jt]sx?$/.test(path));
	const inventory = [];
	for (const path of files) {
		const sourceText = await readFile(path, "utf8");
		for (const statement of sourceFile(path, sourceText).statements) {
			const member = mainModuleSpecifier(statement);
			if (!member) continue;
			inventory.push({
				source: `renderer/${relative(rendererDir, path).replaceAll("\\", "/")}`,
				member,
			});
		}
	}
	return inventory;
}

async function mainModuleInventory(rootDir) {
	const mainDir = join(rootDir, "src", "main");
	const files = (await filesBelow(mainDir)).filter((path) => {
		const name = relative(mainDir, path).replaceAll("\\", "/");
		return /\.[cm]?[jt]sx?$/.test(name) && !/\.(?:test|spec)\.[cm]?[jt]sx?$/.test(name) && !name.endsWith(".d.ts");
	});
	return files.map((path) => ({ source: "main", member: relative(mainDir, path).replaceAll("\\", "/") }));
}

function isDeferredBrowserEntry(entry) {
	return deferredBrowserEntries.has(entryKey(entry.source, entry.member));
}

export async function parityInventory(rootDir) {
	return [
		...(await preloadInventory(rootDir)),
		...(await rendererImportInventory(rootDir)),
		...(await mainModuleInventory(rootDir)),
	].sort((left, right) => entryKey(left.source, left.member).localeCompare(entryKey(right.source, right.member)));
}

export async function validateParityLedger({ rootDir, ledger }) {
	const errors = [];
	if (!Array.isArray(ledger)) return ["parity ledger must be a JSON array"];
	const inventory = await parityInventory(rootDir);
	const inventoryKeys = new Set(inventory.map((entry) => entryKey(entry.source, entry.member)));
	const ledgerKeys = new Set();

	for (const entry of ledger) {
		if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
			errors.push("every ledger entry must be an object");
			continue;
		}
		const source = typeof entry.source === "string" ? entry.source : "<invalid-source>";
		const member = typeof entry.member === "string" ? entry.member : "<invalid-member>";
		const key = entryKey(source, member);
		const display = displayKey(source, member);
		if (ledgerKeys.has(key)) errors.push(`duplicate ${display}`);
		ledgerKeys.add(key);
		if (!inventoryKeys.has(key)) errors.push(`stale ${display}`);
		if (typeof entry.disposition !== "string" || entry.disposition.trim() === "") errors.push(`disposition must be non-empty for ${display}`);

		if (isDeferredBrowserEntry({ source, member })) {
			if (entry.exception !== deferredBrowserRecord) errors.push(`deferred Browser entry must use the exact deferred record for ${display}`);
			if (entry.disposition !== "deferred") errors.push(`deferred Browser entry disposition must be deferred for ${display}`);
			if (entry.owner !== null || entry.task !== null) errors.push(`deferred Browser entry owner and task must be null for ${display}`);
		}

		if (entry.exception !== null) {
			if (entry.exception !== deferredBrowserRecord || !isDeferredBrowserEntry({ source, member })) errors.push(`exception is not allowed for ${display}`);
			if (entry.disposition !== "deferred") errors.push(`exception disposition must be deferred for ${display}`);
			if (entry.owner !== null || entry.task !== null) errors.push(`deferred owner and task must be null for ${display}`);
			continue;
		}

		if (!allowedOwners.has(entry.owner)) errors.push(`owner must be tauri, go, or renderer for ${display}`);
		if (!Number.isInteger(entry.task) || entry.task < 1) errors.push(`task must be a positive integer for ${display}`);
	}

	for (const entry of inventory) {
		const key = entryKey(entry.source, entry.member);
		if (!ledgerKeys.has(key)) errors.push(`missing ${displayKey(entry.source, entry.member)}`);
	}

	return errors;
}

export async function checkParityLedger({ rootDir, ledgerPath }) {
	const ledger = JSON.parse(await readFile(ledgerPath, "utf8"));
	const errors = await validateParityLedger({ rootDir, ledger });
	if (errors.length > 0) throw new Error(errors.join("\n"));
	return ledger.length;
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	const rootDir = resolve(dirname(scriptPath), "..");
	try {
		const count = await checkParityLedger({ rootDir, ledgerPath: join(rootDir, "perf", "parity-ledger.json") });
		process.stdout.write(`Desktop parity ledger covers ${count} entries.\n`);
	} catch (error) {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	}
}
