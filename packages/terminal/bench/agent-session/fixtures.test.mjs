import assert from "node:assert/strict";
import { test } from "node:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { FIXTURES_DIR, listFixtures, loadFixture } from "./fixtures.mjs";
import { listProbes, loadProbe, PROBES_DIR } from "./fixtures.mjs";

test("every fixture directory has a recording and a well-formed size.json", async () => {
	const names = listFixtures();
	assert.ok(names.includes("claude-spinner-10s"), `fixtures: ${names.join(", ")}`);
	for (const name of names) {
		assert.ok(existsSync(join(FIXTURES_DIR, name, "recording")));
		const fixture = await loadFixture(name);
		assert.ok(fixture.recording.length > 0, `${name}: empty recording`);
		assert.ok(fixture.sizes.length >= 1, `${name}: size.json has no entries`);
		assert.equal(fixture.sizes[0].offset, 0, `${name}: first size entry must start at offset 0`);
		let previous = -1;
		for (const size of fixture.sizes) {
			assert.ok(Number.isInteger(size.offset) && size.offset > previous, `${name}: offsets must increase`);
			assert.ok(size.offset <= fixture.recording.length, `${name}: offset past the recording`);
			assert.ok(size.cols >= 1 && size.cols <= 1000 && size.rows >= 1 && size.rows <= 1000, `${name}: grid out of range`);
			previous = size.offset;
		}
	}
});

test("the spinner fixture contains synchronized-output frames", async () => {
	const { recording } = await loadFixture("claude-spinner-10s");
	const text = Buffer.from(recording).toString("latin1");
	const esus = text.split("\x1b[?2026l").length - 1;
	assert.ok(esus >= 50, `expected at least 50 ESU-terminated frames, found ${esus}`);
});

test("every probe has a recording and a well-formed size.json and is not a fixture", async () => {
	const probes = listProbes();
	assert.ok(probes.includes("glyph-probe"), `probes: ${probes.join(", ")}`);
	for (const name of probes) {
		assert.ok(existsSync(join(PROBES_DIR, name, "recording")));
		assert.ok(!listFixtures().includes(name), `${name} must not also be a fixture`);
		const probe = await loadProbe(name);
		assert.ok(probe.recording.length > 0);
		assert.equal(probe.sizes[0].offset, 0);
	}
});

test("the glyph probe holds the rows the evidence script measures", async () => {
	const { recording } = await loadProbe("glyph-probe");
	const text = Buffer.from(recording).toString("utf8");
	for (const marker of ["│ box", "│ rows", "wide: ", "cjk: ", "seq: ", "attrs: ", "band: "]) {
		assert.ok(text.includes(marker), `probe is missing ${JSON.stringify(marker)}`);
	}
	assert.equal(text.split("\x1b[40G|").length - 1, 3, "three rows carry the column-40 marker");
});
