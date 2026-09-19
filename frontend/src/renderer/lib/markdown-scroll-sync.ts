const fence = /^(```|~~~)/;
const heading = /^#{1,6}\s/;

export function headingIndexBeforeLine(content: string, line: number): number {
	const lines = content.split("\n");
	let start = 0;
	if (lines[0] === "---") {
		const end = lines.indexOf("---", 1);
		if (end !== -1) start = end + 1;
	}
	let index = -1;
	let inFence = false;
	for (let i = start; i < lines.length && i < line; i++) {
		const text = lines[i] ?? "";
		if (fence.test(text)) {
			inFence = !inFence;
			continue;
		}
		if (!inFence && heading.test(text)) index++;
	}
	return index;
}
