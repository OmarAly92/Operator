import type { BlockId, FontConfig, TerminalTheme } from "@operator/terminal-core";
import { createPinnedHeaderElement } from "./pinned-header.js";
import { styleVarEntries, styleVarsString } from "./style-vars.js";
import { terminalStylesForDocument } from "./styles.js";

const CLASS_BLOCK = "terminal-block";
const CLASS_LEADING_SPACER = "terminal-spacer";
const CLASS_TRAILING_SPACER = "terminal-spacer";

export type RendererChrome = Readonly<{
	list: HTMLElement;
	leading: HTMLElement;
	trailing: HTMLElement;
	pinned: HTMLElement;
	decorations: HTMLElement;
}>;

export function createRendererChrome(container: HTMLElement, style: string): RendererChrome {
	ensurePackageStyleTag();
	container.style.position = "relative";
	applyScrollOverflow(container);
	container.style.contain = "strict";
	const list = document.createElement("div");
	list.className = "terminal-list";
	list.setAttribute("data-testid", "terminal-block-list");
	list.style.position = "relative";
	const leading = document.createElement("div");
	leading.className = CLASS_LEADING_SPACER;
	const trailing = document.createElement("div");
	trailing.className = CLASS_TRAILING_SPACER;
	list.append(leading, trailing);
	container.append(list);
	const pinned = createPinnedHeaderElement();
	container.insertBefore(pinned, list);
	const decorations = document.createElement("div");
	decorations.className = "terminal-decorations";
	decorations.setAttribute("style", style);
	container.append(decorations);
	return { list, leading, trailing, pinned, decorations };
}

export type StyledParts = Readonly<{
	container: HTMLElement | null;
	blockElements: Iterable<HTMLElement>;
	altRoot: HTMLElement | null;
	decorationLayer: HTMLElement | null;
}>;

export function applyStyleVars(parts: StyledParts, theme: TerminalTheme, font: FontConfig): void {
	const style = styleVarsString(theme, font);
	// The host gets them too, so the surface behind and between the blocks can
	// paint the theme's own background. Without this the gaps between blocks
	// fall through to whatever the embedding app painted, which seams against
	// the blocks whenever the terminal's palette is not the app's.
	//
	// Set them one at a time rather than replacing the style attribute: the
	// container is the one element mount() also styles, and overwriting the
	// attribute drops position/overflow/contain, which stops it being a
	// scroll container at all.
	if (parts.container) {
		const target = parts.container.style;
		for (const [name, value] of styleVarEntries(theme, font)) {
			target.setProperty(name, value);
		}
	}
	for (const element of parts.blockElements) {
		element.setAttribute("style", style);
	}
	if (parts.altRoot) {
		parts.altRoot.setAttribute("style", style);
	}
	if (parts.decorationLayer) {
		parts.decorationLayer.setAttribute("style", style);
	}
}

export function releaseContainer(container: HTMLElement): void {
	container.classList.remove("terminal-link-hover");
	container.replaceChildren();
	container.style.removeProperty("position");
	container.style.removeProperty("overflow");
	container.style.removeProperty("overflow-x");
	container.style.removeProperty("overflow-y");
	container.style.removeProperty("overscroll-behavior-y");
	container.style.removeProperty("contain");
}

export function decorationLayer(parent: HTMLElement | null, name: string): HTMLElement | null {
	if (!parent) return null;
	let layer = parent.querySelector<HTMLElement>(`[data-terminal-layer="${name}"]`);
	if (!layer) {
		layer = document.createElement("div");
		layer.dataset.terminalLayer = name;
		parent.append(layer);
	}
	return layer;
}

export function createBlockSection(id: BlockId, style: string): HTMLElement {
	const section = document.createElement("section");
	section.className = CLASS_BLOCK;
	section.dataset.terminalBlockId = id;
	section.setAttribute("style", style);
	return section;
}

export function createAltRoot(container: HTMLElement, style: string): HTMLElement {
	const root = document.createElement("div");
	root.setAttribute("data-terminal-alt-surface", "");
	root.classList.add("terminal-alt-surface");
	root.setAttribute("style", style);
	container.append(root);
	return root;
}

export function showAltRoot(container: HTMLElement, chrome: RendererChrome, ensureAltRoot: () => HTMLElement, style: string): void {
	container.style.overflow = "hidden";
	container.scrollTop = 0;
	const altRoot = ensureAltRoot();
	altRoot.setAttribute("style", style);
	altRoot.hidden = false;
	chrome.list.hidden = true;
	chrome.pinned.hidden = true;
}

export function showBlockList(container: HTMLElement, chrome: RendererChrome, altRoot: HTMLElement | null): void {
	if (altRoot) {
		altRoot.hidden = true;
	}
	chrome.list.hidden = false;
	applyScrollOverflow(container);
}

export function applyScrollOverflow(container: HTMLElement): void {
	container.style.overflowX = "hidden";
	container.style.overflowY = "auto";
	container.style.setProperty("overscroll-behavior-y", "none");
}

function ensurePackageStyleTag(): HTMLStyleElement {
	const existing = document.head.querySelector<HTMLStyleElement>("style[data-terminal-package]");
	if (existing) {
		// Refresh rather than skip: under HMR the module re-evaluates with new CSS
		// while the previous version's tag survives, leaving current markup styled
		// by a stale stylesheet.
		const current = terminalStylesForDocument();
		if (existing.textContent !== current) existing.textContent = current;
		return existing;
	}
	const tag = document.createElement("style");
	tag.setAttribute("data-terminal-package", "renderer-dom");
	tag.textContent = terminalStylesForDocument();
	document.head.append(tag);
	return tag;
}
