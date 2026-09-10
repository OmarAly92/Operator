const WATCHED = ["react", "react-dom"];

// Two copies of React in one bundle is a silent failure: the second copy's hook
// dispatcher is never installed, so every hook it runs reads null. It surfaces
// only at runtime, as "null is not an object (evaluating '<x>.H.useRef')", and
// only in builds -- the dev dep optimizer flattens bare specifiers, so a
// duplicate that the build resolves per importer never appears in dev.
export function duplicateReactRoots(moduleIds) {
	const roots = new Map();
	for (const id of moduleIds) {
		const normalized = String(id).replace(/\\/g, "/");
		for (const name of WATCHED) {
			const marker = `/node_modules/${name}/`;
			const index = normalized.lastIndexOf(marker);
			if (index === -1) continue;
			const root = normalized.slice(0, index + marker.length - 1);
			if (!roots.has(name)) roots.set(name, new Set());
			roots.get(name).add(root);
		}
	}
	const duplicates = [];
	for (const name of WATCHED) {
		const found = roots.get(name);
		if (found && found.size > 1) duplicates.push(...[...found].sort());
	}
	return duplicates;
}

export function assertSingleReact() {
	return {
		name: "assert-single-react",
		apply: "build",
		buildEnd() {
			const duplicates = duplicateReactRoots([...this.getModuleIds()]);
			if (duplicates.length === 0) return;
			this.error(
				`more than one React copy reached the bundle, which nulls the hook dispatcher at runtime:\n  ${duplicates.join("\n  ")}\nAdd the package to resolve.dedupe in vite.renderer.config.ts.`,
			);
		},
	};
}
