import { readFile, readdir } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const allowedOwners = new Set(["tauri", "go", "renderer"]);
const deferredBrowserRecord = "docs/todo/browser-panel-webview.md";

function entryKey(source, member) {
	return `${source}\u0000${member}`;
}

function displayKey(source, member) {
	return `${source}/${member}`;
}

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

function commentEnd(sourceText, index) {
	if (sourceText[index] !== "/") return null;
	if (sourceText[index + 1] === "/") {
		const newline = sourceText.indexOf("\n", index + 2);
		return newline === -1 ? sourceText.length : newline;
	}
	if (sourceText[index + 1] !== "*") return null;
	const closing = sourceText.indexOf("*/", index + 2);
	return closing === -1 ? sourceText.length : closing + 2;
}

function quotedToken(sourceText, index) {
	const quote = sourceText[index];
	let text = "";
	index += 1;
	while (index < sourceText.length && sourceText[index] !== quote) {
		if (sourceText[index] === "\\") index += 1;
		text += sourceText[index] ?? "";
		index += 1;
	}
	return { token: { type: "name", text }, nextIndex: index + 1 };
}

function tokenizeTypeScript(sourceText) {
	const sourceTokens = [];
	let index = 0;
	while (index < sourceText.length) {
		const character = sourceText[index];
		if (/\s/.test(character)) {
			index += 1;
			continue;
		}
		const nextIndex = commentEnd(sourceText, index);
		if (nextIndex !== null) {
			index = nextIndex;
			continue;
		}
		if (character === '"' || character === "'" || character === "`") {
			const quoted = quotedToken(sourceText, index);
			sourceTokens.push(quoted.token);
			index = quoted.nextIndex;
			continue;
		}
		const identifier = /^[A-Za-z_$][\w$]*/.exec(sourceText.slice(index));
		if (identifier) {
			sourceTokens.push({ type: "name", text: identifier[0] });
			index += identifier[0].length;
			continue;
		}
		sourceTokens.push({ type: "punctuation", text: character });
		index += 1;
	}
	return sourceTokens;
}

function objectProperties(sourceTokens, openIndex) {
	const properties = [];
	let braces = 1;
	let brackets = 0;
	let parentheses = 0;
	let expectsProperty = true;
	for (let index = openIndex + 1; index < sourceTokens.length && braces > 0; index += 1) {
		const token = sourceTokens[index];
		if (token.text === "{") braces += 1;
		if (token.text === "}") braces -= 1;
		if (token.text === "[") brackets += 1;
		if (token.text === "]") brackets -= 1;
		if (token.text === "(") parentheses += 1;
		if (token.text === ")") parentheses -= 1;
		if (braces !== 1 || brackets !== 0 || parentheses !== 0) continue;
		if (token.text === ",") {
			expectsProperty = true;
			continue;
		}
		if (!expectsProperty || token.type !== "name" || sourceTokens[index + 1]?.text !== ":") continue;
		properties.push({ name: token.text, valueIndex: index + 2 });
		expectsProperty = false;
	}
	return properties;
}

async function preloadInventory(rootDir) {
	const path = join(rootDir, "src", "preload.ts");
	const sourceText = await readFile(path, "utf8");
	const sourceTokens = tokenizeTypeScript(sourceText);
	const inventory = [];
	const apiIndex = sourceTokens.findIndex((token, index) => token.text === "api" && sourceTokens[index + 1]?.text === "=" && sourceTokens[index + 2]?.text === "{");
	if (apiIndex === -1) throw new Error("src/preload.ts must declare const api as an object literal");
	for (const namespace of objectProperties(sourceTokens, apiIndex + 2)) {
		if (sourceTokens[namespace.valueIndex]?.text !== "{") continue;
		for (const member of objectProperties(sourceTokens, namespace.valueIndex)) {
			inventory.push({ source: `preload.${namespace.name}`, member: member.name });
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
		for (const match of sourceText.matchAll(/\bfrom\s+"(\.\.\/\.\.\/main\/[^"]+)"/g)) {
			inventory.push({
				source: `renderer/${relative(rendererDir, path).replaceAll("\\", "/")}`,
				member: match[1],
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
	if (entry.source === "preload.browser") return true;
	if (entry.source.startsWith("renderer/") && entry.member === "../../main/browser-view-host") return true;
	return entry.source === "main" && entry.member === "browser-view-host.ts";
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
