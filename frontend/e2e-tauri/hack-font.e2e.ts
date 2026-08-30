import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = fileURLToPath(new URL("..", import.meta.url));
const stylesModule = path.resolve(frontendRoot, "../packages/terminal/ts/renderer-dom/dist/styles.js");

describe("bundled terminal font", () => {
	it("loads Hack and changes the SF Mono cell width", async () => {
		const result = await browser.execute(`
			const styles = await import(${JSON.stringify(`/@fs${stylesModule}`)});
			const tag = document.createElement("style");
			tag.textContent = styles.terminalStylesForDocument();
			document.head.append(tag);
			await document.fonts.load('13px "Hack"', "MMMMMMMMMM");
			const measure = (family) => {
				const node = document.createElement("span");
				node.textContent = "MMMMMMMMMM";
				node.style.cssText = "font-size: 13px; font-family: " + family + "; position: absolute; visibility: hidden; white-space: pre";
				document.body.append(node);
				const width = node.getBoundingClientRect().width;
				node.remove();
				return width;
			};
			return {
				loaded: document.fonts.check('13px "Hack"'),
				hackWidth: measure('"Hack"'),
				sfMonoWidth: measure('"SF Mono"'),
			};
		`);
		assert.equal(result.loaded, true);
		assert.notEqual(result.hackWidth, result.sfMonoWidth);
	});
});
