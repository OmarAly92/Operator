// Generates the Tauri v2 updater JSON feed (<channel>.json) for a release's
// updater archives. Dependency-free ESM so CI runs `node scripts/tauri-feed.mjs`
// directly and node:test unit-tests the pure functions.
//
// The builder is deliberately strict: it refuses invalid semver, missing .sig
// sidecars, wrong OS/architecture assets, cross-channel assets, insecure
// production URLs, duplicate platforms, and any private-key material found in
// the dist directory (spec §5 "Feeds reject ..."). A feature (pr<N>) channel
// can never write latest* manifests (#2270 poisoning class).
//
// macOS permanence: whenever a mac updater archive (.app.tar.gz) is selected,
// the same directory must carry the matching ditto zip, so `opr start` keeps
// finding a real zip to download every release.
import { closeSync, openSync, readdirSync, readFileSync, readSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export const UPDATER_PLATFORM_KEYS = Object.freeze([
	"darwin-aarch64",
	"darwin-x86_64",
	"linux-x86_64",
	"windows-x86_64",
]);

export const VERSION_FREE_ALIASES = Object.freeze([
	"operator-darwin-arm64.zip",
	"operator-darwin-x64.zip",
	"operator-darwin-arm64.dmg",
	"operator-darwin-x64.dmg",
	"operator-win32-x64.exe",
	"operator-linux-x64.AppImage",
]);

export const PRODUCTION_FEED_BASE_URL =
	"https://github.com/OmarAly92/operator/releases/latest/download/";

const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;
const PR_TOKEN = /-pr(\d+)\.\d{12}(?:$|\+)/;

function stripBuildMetadata(version) {
	return version.split("+")[0];
}

export function isValidSemver(version) {
	if (typeof version !== "string") return false;
	const m = SEMVER.exec(version);
	if (!m) return false;
	for (const numeric of [m[1], m[2], m[3]]) {
		if (numeric.length > 1 && numeric.startsWith("0")) return false;
	}
	return true;
}

// assertChannelVersion pins the channel/version contract: stable releases are
// bare x.y.z; feature builds carry -pr<N>.<ts>. Any disagreement throws
// before a feed byte is written.
export function assertChannelVersion(channel, version) {
	if (!isValidSemver(version)) {
		throw new Error(`tauri-feed: '${version}' is not a valid semver version`);
	}
	const bare = stripBuildMetadata(version);
	if (channel === "latest") {
		if (!/^\d+\.\d+\.\d+$/.test(bare)) {
			throw new Error(
				`tauri-feed: stable channel requires a bare x.y.z version with no prerelease, got '${bare}'`,
			);
		}
		return;
	}
	const pr = /^pr(\d+)$/.exec(channel);
	if (!pr) {
		throw new Error(`tauri-feed: unknown channel '${channel}'`);
	}
	const match = PR_TOKEN.exec(bare);
	if (!match || match[1] !== pr[1]) {
		throw new Error(`tauri-feed: version '${bare}' does not carry the pr${pr[1]} channel token`);
	}
}

// updaterPlatformFor maps an updater-archive filename to its canonical Tauri
// platform key, or null for everything that is not one (dmgs, zips, deb/rpm,
// signatures). An arm64 Windows setup exe is NOT mapped to windows-x86_64 —
// a wrong-architecture asset must never enter the feed silently.
export function updaterPlatformFor(filename) {
	if (/\.app\.tar\.gz$/.test(filename)) {
		if (/aarch64|arm64/.test(filename)) return "darwin-aarch64";
		if (/x86_64|(?<=[^a-z])x64|darwin-x64/.test(filename)) return "darwin-x86_64";
		return null;
	}
	if (/\.AppImage$/.test(filename)) {
		if (/arm64|aarch64/.test(filename)) return null;
		if (/amd64|x86_64|(?<=[^a-z])x64/.test(filename)) return "linux-x86_64";
		return null;
	}
	if (/\.exe$/.test(filename) && !filename.endsWith(".sig")) {
		if (/aarch64|arm64/.test(filename)) return null;
		if (/x86_64|win32|(?<=[^a-z])x64/.test(filename)) return "windows-x86_64";
	}
	return null;
}

export function selectUpdaterArchives(filenames, version) {
	const selected = {};
	for (const name of filenames) {
		const platform = updaterPlatformFor(name);
		if (!platform) continue;
		// Version-free aliases (operator-win32-x64.exe and friends) share the
		// dist dir with the versioned archives they shadow; they are not
		// updater inputs. An archive carrying a DIFFERENT version string,
		// however, is contamination and refuses the whole build.
		if (!/\d+\.\d+\.\d+/.test(name)) continue;
		if (!name.includes(stripBuildMetadata(version))) {
			throw new Error(
				`tauri-feed: updater archive '${name}' does not carry this release's version '${stripBuildMetadata(version)}'`,
			);
		}
		if (/-pr\d+\./.test(name) && !PR_TOKEN.test(version)) {
			throw new Error(
				`tauri-feed: cross-channel asset '${name}' carries a feature-pr token on a non-feature channel`,
			);
		}
		if (selected[platform]) {
			throw new Error(
				`tauri-feed: two ${platform} updater archives selected ('${selected[platform]}' and '${name}'); refusing to guess`,
			);
		}
		selected[platform] = name;
	}
	return selected;
}

// validateSignature accepts exactly the base64-encoded minisign signature blob
// `tauri build` writes beside each updater archive, and rejects anything that
// smells like private-key material.
export function validateSignature(content) {
	const trimmed = String(content ?? "").trim();
	if (!trimmed) throw new Error("tauri-feed: signature file is empty");
	if (!/^[A-Za-z0-9+/]+=*$/.test(trimmed)) {
		throw new Error("tauri-feed: signature file is not a base64 minisign blob");
	}
	let decoded;
	try {
	 decoded = Buffer.from(trimmed, "base64").toString("utf8");
	} catch {
		throw new Error("tauri-feed: signature file is not valid base64");
	}
	// Minisign SECRET-key files announce themselves exactly; a real signature's
	// own comment may legitimately contain the words "secret key" (the tauri
	// signer writes "signature from tauri secret key").
	if (PRIVATE_KEY_MATERIAL.test(decoded)) {
		throw new Error("tauri-feed: private-key material must never appear in a feed input");
	}
	const lines = decoded.trimEnd().split("\n");
	if (!lines[0].startsWith("untrusted comment:") || lines.length < 4 || !lines[2].startsWith("trusted comment: ")) {
		throw new Error("tauri-feed: signature file is not a minisign signature");
	}
	let packet;
	try {
		packet = Buffer.from(lines[1], "base64");
	} catch {
		throw new Error("tauri-feed: signature packet is not valid base64");
	}
	if (packet.length !== 74 || packet.subarray(0, 2).toString("ascii") !== "ED") {
		throw new Error("tauri-feed: signature packet is malformed");
	}
	if (PRIVATE_KEY_MATERIAL.test(decoded)) {
		throw new Error("tauri-feed: private-key material must never appear in a feed input");
	}
}

// Exact private-key markers only — never the loose "secret key" comment
// heuristic, which false-positived on genuine Tauri signatures.
const PRIVATE_KEY_MATERIAL = /encrypted secret key|-----BEGIN/i;
// Minisign tags every packet with a two-byte algorithm prefix: signatures are
// "ED", secret keys are "RS". Matching the tag (not comment prose) catches a
// renamed or comment-stripped secret key while never tripping on real
// signatures.
const MINISIGN_SECRET_KEY_TAG = "RS";

const PRIVATE_KEY_NAME = /(^|[-_.])(private|secret)[-_.]?key$|\.key$|\.pem$|id_rsa/i;

// looksLikePrivateKeyMaterial recognises minisign secret keys by content, not
// by name: the exact material markers above, or an untrusted-comment file
// whose base64 payload decodes to a packet carrying the secret-key tag.
export function looksLikePrivateKeyMaterial(text) {
	if (PRIVATE_KEY_MATERIAL.test(String(text))) return true;
	const lines = String(text).split("\n");
	for (let i = 0; i < lines.length - 1; i++) {
		if (!/^untrusted comment:/i.test(lines[i])) continue;
		const payload = lines[i + 1].trim();
		if (!payload || !/^[A-Za-z0-9+/]+=*$/.test(payload)) continue;
		const packet = Buffer.from(payload, "base64");
		if (packet.length >= 8 && packet.subarray(0, 2).toString("ascii") === MINISIGN_SECRET_KEY_TAG) {
			return true;
		}
	}
	return false;
}

const SCAN_PREFIX_BYTES = 64 * 1024;

// assertNoPrivateKeyMaterial scans a dist directory for private-key material
// and refuses to generate feeds while any exists. EVERY regular file is
// content-scanned (a bounded prefix read — keys hide under innocent names like
// `signing_key` or `t18key`, exactly what `tauri signer generate -w` writes),
// and suspiciously NAMED files are additionally read in full. Only content
// proves a file safe; a name never does.
export function assertNoPrivateKeyMaterial(dir) {
	for (const name of readdirSync(dir)) {
		const path = join(dir, name);
		const refuse = () =>
			new Error(
				`tauri-feed: private-key material detected in dist dir ('${name}'); remove it before generating feeds`,
			);
		let stats;
		try {
			stats = statSync(path);
		} catch (err) {
			throw new Error(`tauri-feed: cannot stat '${path}' while scanning for private-key material: ${err.message}`);
		}
		// Directories and other non-regular entries have no content to scan.
		if (!stats.isFile()) continue;
		let head;
		try {
			const fd = openSync(path, "r");
			try {
				head = Buffer.alloc(Math.min(SCAN_PREFIX_BYTES, stats.size));
				head = head.subarray(0, readSync(fd, head, 0, head.length, 0));
			} finally {
				closeSync(fd);
			}
		} catch (err) {
			throw new Error(`tauri-feed: cannot read '${path}' while scanning for private-key material: ${err.message}`);
		}
		// latin1 keeps a byte-for-byte mapping so the ASCII markers cannot be
		// corrupted by multibyte decoding.
		if (looksLikePrivateKeyMaterial(head.toString("latin1"))) {
			throw refuse();
		}
		if (PRIVATE_KEY_NAME.test(name) && PRIVATE_KEY_MATERIAL.test(readFileSync(path, "latin1"))) {
			throw refuse();
		}
	}
}

// feedUrl joins a feed base URL and an asset name, refusing insecure http
// outside loopback unless allowInsecure opts in (local dev servers only).
export function feedUrl(nameOrUrl, { base = PRODUCTION_FEED_BASE_URL, allowInsecure = false } = {}) {
	const raw = nameOrUrl.includes("://") ? nameOrUrl : `${base}${nameOrUrl}`;
	let url;
	try {
		url = new URL(raw);
	} catch {
		throw new Error(`tauri-feed: unparseable feed url '${raw}'`);
	}
	if (url.protocol === "https:") return raw;
	const loopback =
		(url.hostname === "127.0.0.1" || url.hostname === "localhost" || url.hostname === "::1") &&
		url.protocol === "http:";
	if (!loopback || !allowInsecure) {
		throw new Error(`tauri-feed: insecure production feed url '${raw}' (https required)`);
	}
	return raw;
}

// buildTauriFeed serializes the v2 updater manifest. Output is deterministic:
// fixed key order, canonical platform order, 2-space JSON, trailing newline.
export function buildTauriFeed({ version, notes = "", pubDate, platforms, allowInsecure = false }) {
	const ordered = [...platforms].sort((a, b) => a.key.localeCompare(b.key));
	const seen = new Set();
	const platformMap = {};
	for (const entry of ordered) {
		if (!UPDATER_PLATFORM_KEYS.includes(entry.key)) {
			throw new Error(`tauri-feed: unknown updater platform '${entry.key}'`);
		}
		if (seen.has(entry.key)) {
			throw new Error(`tauri-feed: duplicate platform entry '${entry.key}'`);
		}
		seen.add(entry.key);
		if (!entry.signature) throw new Error(`tauri-feed: platform '${entry.key}' has no signature`);
		feedUrl(entry.url, { allowInsecure });
		platformMap[entry.key] = { signature: entry.signature, url: entry.url };
	}
	return `${JSON.stringify({ version, notes, pub_date: pubDate, platforms: platformMap }, null, 2)}\n`;
}

export function expectedFeedFilenames(channel) {
	return [`${channel}.json`];
}

export function assertNoCrossChannelFeedNames(channel, writtenNames) {
	if (/^pr\d+$/.test(channel)) {
		for (const name of writtenNames) {
			if (/^latest/.test(name)) {
				throw new Error(
					`tauri-feed: feature channel '${channel}' produced forbidden manifest '${name}'; feature builds must never write latest* feeds`,
				);
			}
		}
	}
}

export function missingAliases(presentNames) {
	const present = new Set(presentNames);
	return VERSION_FREE_ALIASES.filter((alias) => !present.has(alias));
}

// generateFeeds writes `<channel>.json` for everything already sitting in dir.
// options:
//   releaseDate     ISO timestamp stamped into the feed
//   notes           release notes string for the JSON feed
//   baseUrl         release download base the asset names are resolved against;
//                   the Tauri updater rejects relative urls (default production)
//   allowInsecure   permits loopback http urls (local dev only)
//   skipMacZipRequirement  drops the permanent-mac-zip invariant (tests only)
export async function generateFeeds(dir, rawVersion, channel, options = {}) {
	const {
		releaseDate = new Date().toISOString(),
		notes = "",
		baseUrl = PRODUCTION_FEED_BASE_URL,
		allowInsecure = false,
		skipMacZipRequirement = false,
	} = options;
	assertChannelVersion(channel, rawVersion);
	assertNoPrivateKeyMaterial(dir);

	const names = readdirSync(dir).filter((name) => !name.endsWith(".sig"));
	const selected = selectUpdaterArchives(names, rawVersion);
	const platforms = Object.keys(selected);
	if (platforms.length === 0) {
		throw new Error(`tauri-feed: no updater archives for version '${rawVersion}' found in ${dir}`);
	}

	const entries = [];
	for (const key of UPDATER_PLATFORM_KEYS) {
		const archive = selected[key];
		if (!archive) continue;
		const sigPath = `${join(dir, archive)}.sig`;
		let signature;
		try {
			signature = readFileSync(sigPath, "utf8");
		} catch {
			throw new Error(`tauri-feed: missing required .sig sidecar '${sigPath}'`);
		}
		validateSignature(signature);
		entries.push({ key, url: feedUrl(archive, { base: baseUrl, allowInsecure }), signature: signature.trim() });
	}

	requireMacDittoZips(names, rawVersion, selected, { skip: skipMacZipRequirement });

	writeFileSync(
		join(dir, `${channel}.json`),
		buildTauriFeed({
			version: stripBuildMetadata(rawVersion),
			notes,
			pubDate: releaseDate,
			platforms: entries,
			allowInsecure,
		}),
	);

	const written = readdirSync(dir).filter((name) => name.endsWith(".json"));
	assertNoCrossChannelFeedNames(channel, written);
	return written.sort();
}

// requireMacDittoZips enforces macOS permanence: every mac updater archive in
// the feed must be accompanied by its ditto zip.
function requireMacDittoZips(names, version, selected, { skip = false } = {}) {
	if (skip) return;
	const bare = stripBuildMetadata(version);
	const macZipFor = (archToken) =>
		names.find((name) => name.endsWith(".zip") && name.includes("darwin") && name.includes(archToken) && name.includes(bare));
	for (const [platform, archToken] of [
		["darwin-aarch64", "arm64"],
		["darwin-x86_64", "x64"],
	]) {
		if (!selected[platform]) continue;
		if (!macZipFor(archToken)) {
			throw new Error(
				`tauri-feed: no ditto zip beside the ${platform} updater archive; the permanent ${archToken} zip opr start downloads would go missing`,
			);
		}
	}
}

// CLI: node scripts/tauri-feed.mjs <dir> <version> <channel>
//        [--release-date <iso>] [--notes <text>] [--base-url <https://.../download/vX.Y.Z/>]
if (import.meta.url === `file://${process.argv[1]}`) {
	const [, , dir, version, channel] = process.argv;
	if (!dir || !version || !channel) {
		process.stderr.write(
			"usage: node tauri-feed.mjs <dir> <version> <channel> [--release-date <iso>] [--notes <text>] [--base-url <url>]\n",
		);
		process.exit(2);
	}
	const flagValue = (flag) => {
		const index = process.argv.indexOf(flag);
		return index === -1 ? undefined : process.argv[index + 1];
	};
	generateFeeds(dir, version, channel, {
		releaseDate: flagValue("--release-date") ?? new Date().toISOString(),
		notes: flagValue("--notes") ?? "",
		baseUrl: flagValue("--base-url") ?? PRODUCTION_FEED_BASE_URL,
	})
		.then((written) => {
			process.stdout.write(`${written.join("\n")}\n`);
		})
		.catch((err) => {
			process.stderr.write(`${err.stack || err}\n`);
			process.exit(1);
		});
}
