import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
	PRODUCTION_FEED_BASE_URL,
	UPDATER_PLATFORM_KEYS,
	VERSION_FREE_ALIASES,
	assertChannelVersion,
	assertNoCrossChannelFeedNames,
	assertNoPrivateKeyMaterial,
	buildTauriFeed,
	expectedFeedFilenames,
	feedUrl,
	generateFeeds,
	isValidSemver,
	missingAliases,
	selectUpdaterArchives,
	updaterPlatformFor,
	validateSignature,
} from "./tauri-feed.mjs";

const V = "0.10.4";
const NIGHTLY_V = "0.10.5-nightly.202608240900";
const PR_V = "0.10.4-pr2270.202608240900";

function fixtureDir(files) {
	const dir = mkdtempSync(join(tmpdir(), "tauri-feed-test-"));
	for (const [name, content] of Object.entries(files)) {
		writeFileSync(join(dir, name), content);
	}
	return dir;
}

function fakeSignature(label = "signature") {
	const packet = Buffer.concat([
		Buffer.from("ED", "ascii"),
		Buffer.alloc(8, 0x11),
		Buffer.alloc(64, 0x22),
	]);
	const armored = [
		`untrusted comment: minisign ${label}`,
		packet.toString("base64"),
		"trusted comment: timestamp:1740000000\tfile:Operator.app.tar.gz",
		Buffer.alloc(64, 0x33).toString("base64"),
	].join("\n");
	return Buffer.from(armored, "utf8").toString("base64");
}

// The tauri signer's own comment mentions the words "secret key"; only an
// actual encrypted-secret-key FILE must be refused.
const TAURI_REAL_COMMENT = "signature from tauri secret key";

function fakeSecretKey() {
	const packet = Buffer.concat([
		Buffer.from("RS", "ascii"),
		Buffer.alloc(102, 0x44),
	]);
	const armored = [
		"untrusted comment: minisign encrypted secret key",
		packet.toString("base64"),
	].join("\n");
	return Buffer.from(armored, "utf8").toString("base64");
}

// A minisign SECRET-key FILE as `tauri signer generate -w <path>` writes it:
// plaintext armor (not base64-wrapped like a .sig), and in practice named
// whatever the operator chose at the CLI — t18key, key, signing_key.
function fakeSecretKeyFile(comment = "minisign encrypted secret key") {
	const packet = Buffer.concat([
		Buffer.from("RS", "ascii"),
		Buffer.alloc(102, 0x44),
	]);
	return [`untrusted comment: ${comment}`, packet.toString("base64")].join("\n") + "\n";
}

const BASE_FILES = () => ({
	"operator-darwin-arm64-0.10.4.app.tar.gz": "tar",
	"operator-darwin-arm64-0.10.4.app.tar.gz.sig": fakeSignature(),
	"Operator_0.10.4_x64-setup.exe": "nsis",
	"Operator_0.10.4_x64-setup.exe.sig": fakeSignature(),
	"operator_0.10.4_amd64.AppImage": "appimage",
	"operator_0.10.4_amd64.AppImage.sig": fakeSignature(),
	"Operator-darwin-arm64-0.10.4.zip": "ditto zip",
});

test("isValidSemver accepts strict x.y.z with prerelease and build metadata", () => {
	assert.equal(isValidSemver("0.10.4"), true);
	assert.equal(isValidSemver("0.10.5-nightly.202608240900"), true);
	assert.equal(isValidSemver("0.10.4-pr2270.202608240900+ab12cd3"), true);
	assert.equal(isValidSemver("01.2.3"), false);
	assert.equal(isValidSemver("0.10"), false);
	assert.equal(isValidSemver("not-a-version"), false);
	assert.equal(isValidSemver(""), false);
	assert.equal(isValidSemver("0.10.4-"), false);
});

test("assertChannelVersion rejects channel/version disagreement", () => {
	assertChannelVersion("latest", V);
	assertChannelVersion("nightly", NIGHTLY_V);
	assertChannelVersion("pr2270", PR_V);
	assert.throws(() => assertChannelVersion("latest", NIGHTLY_V), /prerelease/);
	assert.throws(() => assertChannelVersion("latest", PR_V), /prerelease/);
	assert.throws(() => assertChannelVersion("nightly", V), /nightly/);
	assert.throws(() => assertChannelVersion("pr2270", V), /pr2270/);
	assert.throws(() => assertChannelVersion("nightly", PR_V), /channel/);
	assert.throws(() => assertChannelVersion("pr2270", NIGHTLY_V), /channel/);
	assert.throws(() => assertChannelVersion("latest", "bogus"), /semver/i);
});

test("updaterPlatformFor maps updater archives and ignores release extras", () => {
	assert.equal(updaterPlatformFor("operator-darwin-arm64-0.10.4.app.tar.gz"), "darwin-aarch64");
	assert.equal(updaterPlatformFor("operator-darwin-x64-0.10.4.app.tar.gz"), "darwin-x86_64");
	assert.equal(updaterPlatformFor("Operator_0.10.4_x64-setup.exe"), "windows-x86_64");
	assert.equal(updaterPlatformFor("operator_0.10.4_amd64.AppImage"), "linux-x86_64");
	assert.equal(updaterPlatformFor("Operator.dmg"), null);
	assert.equal(updaterPlatformFor("operator-darwin-arm64-0.10.4.zip"), null);
	assert.equal(updaterPlatformFor("operator_0.10.4_amd64.deb"), null);
	assert.equal(updaterPlatformFor("operator-0.10.4.x86_64.rpm"), null);
	assert.equal(updaterPlatformFor("Operator_0.10.4_x64-setup.exe.sig"), null);
	assert.equal(updaterPlatformFor("Operator_0.10.4_arm64-setup.exe"), null);
});

test("selectUpdaterArchives picks one updater archive per platform", () => {
	const names = [
		"operator-darwin-arm64-0.10.4.app.tar.gz",
		"operator-darwin-x64-0.10.4.app.tar.gz",
		"Operator_0.10.4_x64-setup.exe",
		"operator_0.10.4_amd64.AppImage",
		"Operator_0.10.4_aarch64.dmg",
		"Operator-darwin-arm64-0.10.4.zip",
	];
	const sel = selectUpdaterArchives(names, V);
	assert.deepEqual(sel["darwin-aarch64"], "operator-darwin-arm64-0.10.4.app.tar.gz");
	assert.deepEqual(sel["darwin-x86_64"], "operator-darwin-x64-0.10.4.app.tar.gz");
	assert.deepEqual(sel["windows-x86_64"], "Operator_0.10.4_x64-setup.exe");
	assert.deepEqual(sel["linux-x86_64"], "operator_0.10.4_amd64.AppImage");
});

test("selectUpdaterArchives skips version-free aliases beside versioned archives", () => {
	const names = [
		"operator-darwin-arm64-0.10.4.app.tar.gz",
		"operator-win32-x64.exe",
		"operator-linux-x64.AppImage",
		"operator-darwin-arm64.zip",
	];
	const sel = selectUpdaterArchives(names, V);
	assert.deepEqual(sel["darwin-aarch64"], "operator-darwin-arm64-0.10.4.app.tar.gz");
	assert.equal(sel["windows-x86_64"], undefined);
	assert.equal(sel["linux-x86_64"], undefined);
});

test("selectUpdaterArchives rejects duplicate platforms and version-mismatched assets", () => {
	assert.throws(
		() =>
			selectUpdaterArchives(
				[
					"operator-darwin-arm64-0.10.4.app.tar.gz",
					"Operator-darwin-aarch64-0.10.4.app.tar.gz",
				],
				V,
			),
		/two darwin-aarch64 updater archives|duplicate/i,
	);
	assert.throws(
		() =>
			selectUpdaterArchives(["Operator_0.10.5_x64-setup.exe"], V),
		/does not carry this release's version/,
	);
});

test("selectUpdaterArchives rejects cross-channel assets", () => {
	assert.throws(
		() => selectUpdaterArchives(["operator-darwin-arm64-0.10.4-nightly.202608240900.app.tar.gz"], V),
		/cross-channel|-nightly\./,
	);
	assert.throws(
		() => selectUpdaterArchives(["operator-darwin-arm64-0.10.4-pr2270.202608240900.app.tar.gz"], V),
		/cross-channel|-pr\d+\./,
	);
	assert.doesNotThrow(() =>
		selectUpdaterArchives(["operator-darwin-arm64-0.10.5-nightly.202608240900.app.tar.gz"], NIGHTLY_V),
	);
});

test("validateSignature accepts a Tauri minisign signature blob and rejects junk and secret keys", () => {
	assert.doesNotThrow(() => validateSignature(fakeSignature()));
	assert.doesNotThrow(() => validateSignature(fakeSignature(TAURI_REAL_COMMENT)));
	assert.throws(() => validateSignature(""), /empty/);
	assert.throws(() => validateSignature("not base64!!"), /base64/);
	assert.throws(
		() => validateSignature(Buffer.from("untrusted comment: plaintext", "utf8").toString("base64")),
		/minisign/,
	);
	assert.throws(() => validateSignature(fakeSecretKey()), /private-key material/);
});

test("assertNoPrivateKeyMaterial refuses a dist dir carrying private key files", () => {
	const dir = fixtureDir({
		"private.key": "untrusted comment: minisign encrypted secret key\nABC=",
	});
	assert.throws(() => assertNoPrivateKeyMaterial(dir), /private-key material/);
	rmSync(dir, { recursive: true, force: true });
});

test("assertNoPrivateKeyMaterial refuses an innocently named minisign secret key", () => {
	const dir = fixtureDir({ ...BASE_FILES(), signing_key: fakeSecretKeyFile() });
	assert.throws(() => assertNoPrivateKeyMaterial(dir), /private-key material/);
	rmSync(dir, { recursive: true, force: true });
});

test("assertNoPrivateKeyMaterial refuses comment-stripped secret-key packets by structure", () => {
	const dir = fixtureDir({
		...BASE_FILES(),
		"release-notes.txt": fakeSecretKeyFile("operator release notes"),
	});
	assert.throws(() => assertNoPrivateKeyMaterial(dir), /private-key material/);
	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds refuses to run while a signing_key sits in the dist", async () => {
	const dir = fixtureDir({ ...BASE_FILES(), signing_key: fakeSecretKeyFile() });
	await assert.rejects(() => generateFeeds(dir, V, "latest", {}), /private-key material/);
	rmSync(dir, { recursive: true, force: true });
});

test("feedUrl enforces https outside loopback", () => {
	assert.equal(feedUrl("latest.json", { base: PRODUCTION_FEED_BASE_URL }), `${PRODUCTION_FEED_BASE_URL}latest.json`);
	assert.throws(
		() => feedUrl("latest.json", { base: "http://github.com/OmarAly92/operator/releases/latest/download/" }),
		/insecure|https/,
	);
	assert.throws(() => feedUrl("http://evil.example/a.tar.gz"), /insecure|https/);
	const dev = feedUrl("nightly.json", {
		base: "http://127.0.0.1:9876/",
		allowInsecure: true,
	});
	assert.equal(dev, "http://127.0.0.1:9876/nightly.json");
});

test("buildTauriFeed serializes deterministically with canonical platform order", () => {
	const platforms = [
		{ key: "windows-x86_64", url: "Operator_0.10.4_x64-setup.exe", signature: "SIGWIN" },
		{ key: "darwin-aarch64", url: "operator-darwin-arm64-0.10.4.app.tar.gz", signature: "SIGARM" },
	];
	const first = buildTauriFeed({ version: V, notes: "n", pubDate: "2026-08-24T00:00:00Z", platforms });
	const second = buildTauriFeed({
		version: V,
		notes: "n",
		pubDate: "2026-08-24T00:00:00Z",
		platforms: [...platforms].reverse(),
	});
	assert.equal(first, second);
	const parsed = JSON.parse(first);
	assert.equal(parsed.version, V);
	assert.equal(parsed.pub_date, "2026-08-24T00:00:00Z");
	assert.deepEqual(Object.keys(parsed.platforms), ["darwin-aarch64", "windows-x86_64"]);
	assert.equal(parsed.platforms["darwin-aarch64"].signature, "SIGARM");
	assert.ok(first.indexOf('"darwin-aarch64"') < first.indexOf('"windows-x86_64"'));
});

test("buildTauriFeed rejects unknown and duplicate platforms", () => {
	assert.throws(
		() =>
			buildTauriFeed({
				version: V,
				pubDate: "2026-08-24T00:00:00Z",
				platforms: [{ key: "sunos-sparc", url: "x", signature: "s" }],
			}),
		/platform/,
	);
	assert.throws(
		() =>
			buildTauriFeed({
				version: V,
				pubDate: "2026-08-24T00:00:00Z",
				platforms: [
					{ key: "darwin-aarch64", url: "a", signature: "1" },
					{ key: "darwin-aarch64", url: "b", signature: "2" },
				],
			}),
		/duplicate/,
	);
});

test("expectedFeedFilenames keeps pr channels off latest*/nightly*", () => {
	assert.deepEqual(expectedFeedFilenames("latest"), ["latest.json", "latest.yml", "latest-mac.yml", "latest-linux.yml"]);
	assert.deepEqual(expectedFeedFilenames("nightly"), [
		"nightly.json",
		"nightly.yml",
		"nightly-mac.yml",
		"nightly-linux.yml",
	]);
	assert.deepEqual(expectedFeedFilenames("pr2270"), [
		"pr2270.json",
		"pr2270.yml",
		"pr2270-mac.yml",
		"pr2270-linux.yml",
	]);
	assert.throws(() => assertNoCrossChannelFeedNames("pr2270", ["latest-mac.yml"]), /latest/);
	assert.throws(() => assertNoCrossChannelFeedNames("pr2270", ["nightly.json"]), /nightly/);
	assert.doesNotThrow(() => assertNoCrossChannelFeedNames("pr2270", ["pr2270.json", "pr2270-mac.yml"]));
});

test("missingAliases reports every unpublished version-free alias", () => {
	assert.deepEqual(missingAliases(VERSION_FREE_ALIASES), []);
	assert.deepEqual(missingAliases([]), [...VERSION_FREE_ALIASES]);
	const missing = missingAliases(["operator-darwin-arm64.zip", "operator-win32-x64.exe"]);
	assert.ok(missing.includes("operator-darwin-x64.zip"));
	assert.ok(missing.includes("operator-darwin-arm64.dmg"));
	assert.equal(VERSION_FREE_ALIASES.length, 6);
});

test("generateFeeds writes the Tauri JSON feed plus compat YAMLs and no blockmaps", async () => {
	const dir = fixtureDir(BASE_FILES());
	await generateFeeds(dir, V, "latest", { releaseDate: "2026-08-24T00:00:00Z" });

	const json = JSON.parse(readFileSync(join(dir, "latest.json"), "utf8"));
	assert.equal(json.version, V);
	assert.equal(json.platforms["darwin-aarch64"].url, "operator-darwin-arm64-0.10.4.app.tar.gz");
	assert.ok(json.platforms["darwin-aarch64"].signature.length > 0);
	assert.equal(json.platforms["linux-x86_64"].url, "operator_0.10.4_amd64.AppImage");

	const names = readdirSync(dir).sort();
	assert.ok(names.includes("latest-mac.yml"));
	assert.ok(names.includes("latest.yml"));
	assert.ok(names.includes("latest-linux.yml"));
	assert.ok(!names.some((name) => name.endsWith(".blockmap")));

	const macYml = readFileSync(join(dir, "latest-mac.yml"), "utf8");
	assert.ok(macYml.includes("url: Operator-darwin-arm64-0.10.4.zip"));
	const winYml = readFileSync(join(dir, "latest.yml"), "utf8");
	assert.ok(winYml.includes("Operator_0.10.4_x64-setup.exe"));

	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds rejects a missing .sig sidecar", async () => {
	const files = BASE_FILES();
	delete files["Operator_0.10.4_x64-setup.exe.sig"];
	const dir = fixtureDir(files);
	await assert.rejects(() => generateFeeds(dir, V, "latest", {}), /\.sig/);
	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds requires the macOS ditto zip beside every mac updater archive", async () => {
	const files = BASE_FILES();
	delete files["Operator-darwin-arm64-0.10.4.zip"];
	const dir = fixtureDir(files);
	await assert.rejects(() => generateFeeds(dir, V, "latest", {}), /ditto zip|latest-mac\.yml|zip/);
	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds refuses private-key material in the dist directory", async () => {
	const dir = fixtureDir({ ...BASE_FILES(), "tauri.key": "untrusted comment: minisign encrypted secret key\nAAA=" });
	await assert.rejects(() => generateFeeds(dir, V, "latest", {}), /private-key material/);
	rmSync(dir, { recursive: true, force: true });
});

test("generateFeeds never writes stable or nightly feeds for a feature channel", async () => {
	const sig = fakeSignature();
	const dir = fixtureDir({
		[`operator-darwin-arm64-${PR_V}.app.tar.gz`]: "tar",
		[`operator-darwin-arm64-${PR_V}.app.tar.gz.sig`]: sig,
		[`Operator_${PR_V}_x64-setup.exe`]: "nsis",
		[`Operator_${PR_V}_x64-setup.exe.sig`]: sig,
		"operator-darwin-arm64-0.10.4.zip": "stale zip from another channel",
	});
	await generateFeeds(dir, PR_V, "pr2270", { releaseDate: "2026-08-24T00:00:00Z", skipMacZipRequirement: true });
	const names = readdirSync(dir);
	assert.ok(names.includes("pr2270.json"));
	assert.ok(!names.some((name) => /^latest/.test(name)));
	assert.ok(!names.some((name) => /^nightly/.test(name)));
	rmSync(dir, { recursive: true, force: true });
});

test("UPDATER_PLATFORM_KEYS lists the four canonical Tauri targets", () => {
	assert.deepEqual([...UPDATER_PLATFORM_KEYS], [
		"darwin-aarch64",
		"darwin-x86_64",
		"linux-x86_64",
		"windows-x86_64",
	]);
});

test("tauri.release.conf.json bakes the production updater surface", () => {
	const conf = JSON.parse(readFileSync(join(import.meta.dirname, "..", "src-tauri", "tauri.release.conf.json"), "utf8"));
	assert.equal(conf.bundle.createUpdaterArtifacts, true);
	assert.ok(conf.plugins.updater, "updater plugin config must exist for the bundler");
	const base = conf.plugins["operator-updates"].feedBaseUrl;
	assert.match(base, /^https:\/\//);
	assert.ok(base.endsWith("/releases/latest/download/"));
	assert.equal(base, PRODUCTION_FEED_BASE_URL);
});
