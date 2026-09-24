/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { describe, expect, it } from "vitest";
import { detectLinks, type ParsedLink } from "./link-parsing";
import { testCol, testColEnd, testLinksWithSuffix, testRow, testRowEnd } from "./link-parsing-cases";

describe('TerminalLinkParsing', () => {
	describe('detectLinks', () => {
		describe('should detect file names in git diffs', () => {
			it('--- a/foo/bar', () => {
				['a', 'c', 'w', 'i', 'o'].forEach(prefix => {
					expect(
						detectLinks(`--- ${prefix}/foo/bar`, "posix")).toStrictEqual(
						[
							{
								path: {
									index: 6,
									text: 'foo/bar'
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
				});
			});
			it('+++ b/foo/bar', () => {
				['b', 'c', 'w', 'i', 'o'].forEach(prefix => {
					expect(
						detectLinks(`+++ ${prefix}/foo/bar`, "posix")).toStrictEqual(
						[
							{
								path: {
									index: 6,
									text: 'foo/bar'
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
				});
			});
			it('diff --git a/foo/bar b/foo/baz', () => {
				[['a', 'b'], ['c', 'w'], ['i', 'o']].forEach(([sourcePrefix, destinationPrefix]) => {
					expect(
						detectLinks(`diff --git ${sourcePrefix}/foo/bar ${destinationPrefix}/foo/baz`, "posix")).toStrictEqual(
						[
							{
								path: {
									index: 13,
									text: 'foo/bar'
								},
								prefix: undefined,
								suffix: undefined
							},
							{
								path: {
									index: 23,
									text: 'foo/baz'
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
				});
			});
			it('numeric prefixes used by git diff --no-index', () => {
				expect(
					[
						detectLinks('--- 1/foo/bar', "posix"),
						detectLinks('+++ 2/foo/baz', "posix"),
						detectLinks('diff --git 1/foo/bar 2/foo/baz', "posix")
					]).toStrictEqual(
					[
						[{
							path: { index: 6, text: 'foo/bar' },
							prefix: undefined,
							suffix: undefined
						}],
						[{
							path: { index: 6, text: 'foo/baz' },
							prefix: undefined,
							suffix: undefined
						}],
						[{
							path: { index: 13, text: 'foo/bar' },
							prefix: undefined,
							suffix: undefined
						}, {
							path: { index: 23, text: 'foo/baz' },
							prefix: undefined,
							suffix: undefined
						}]
					] as ParsedLink[][]
				);
			});
			it('reversed numeric prefixes used by git diff --no-index -R', () => {
				expect(
					[
						detectLinks('--- 2/foo/baz', "posix"),
						detectLinks('+++ 1/foo/bar', "posix"),
						detectLinks('diff --git 2/foo/baz 1/foo/bar', "posix")
					]).toStrictEqual(
					[
						[{
							path: { index: 6, text: 'foo/baz' },
							prefix: undefined,
							suffix: undefined
						}],
						[{
							path: { index: 6, text: 'foo/bar' },
							prefix: undefined,
							suffix: undefined
						}],
						[{
							path: { index: 13, text: 'foo/baz' },
							prefix: undefined,
							suffix: undefined
						}, {
							path: { index: 23, text: 'foo/bar' },
							prefix: undefined,
							suffix: undefined
						}]
					] as ParsedLink[][]
				);
			});
			it('ordinary numeric line suffix', () => {
				expect(
					detectLinks('foo 1', "posix")).toStrictEqual(
					[{
						path: { index: 0, text: 'foo' },
						prefix: undefined,
						suffix: {
							row: 1,
							col: undefined,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: { index: 3, text: ' 1' }
						}
					}] as ParsedLink[]
				);
			});
			it('numeric suffix followed by a path separator', () => {
				expect(
					detectLinks('foo 1/bar', "posix")).toStrictEqual(
					[{
						path: { index: 4, text: '1/bar' },
						prefix: undefined,
						suffix: undefined
					}] as ParsedLink[]
				);
			});
			it('ordinary numeric line suffix after diff --git text', () => {
				expect(
					detectLinks('diff --git foo.ts:123', "posix")).toStrictEqual(
					[{
						path: { index: 11, text: 'foo.ts' },
						prefix: undefined,
						suffix: {
							row: 123,
							col: undefined,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: { index: 17, text: ':123' }
						}
					}] as ParsedLink[]
				);
			});
		});

		describe('should detect 3 suffix links on a single line', () => {
			for (let i = 0; i < testLinksWithSuffix.length - 2; i++) {
				const link1 = testLinksWithSuffix[i];
				const link2 = testLinksWithSuffix[i + 1];
				const link3 = testLinksWithSuffix[i + 2];
				const line = ` ${link1.link} ${link2.link} ${link3.link} `;
				it('`' + line.replaceAll('\u00A0', '<nbsp>') + '`', () => {
					expect(detectLinks(line, "posix").length).toBe( 3);
					expect(link1.suffix).toBeTruthy();
					expect(link2.suffix).toBeTruthy();
					expect(link3.suffix).toBeTruthy();
					const detectedLink1: ParsedLink = {
						prefix: link1.prefix ? {
							index: 1,
							text: link1.prefix
						} : undefined,
						path: {
							index: 1 + (link1.prefix?.length ?? 0),
							text: link1.link.replace(link1.suffix!, '').replace(link1.prefix || '', '')
						},
						suffix: {
							row: link1.hasRow ? testRow : undefined,
							col: link1.hasCol ? testCol : undefined,
							rowEnd: link1.hasRowEnd ? testRowEnd : undefined,
							colEnd: link1.hasColEnd ? testColEnd : undefined,
							suffix: {
								index: 1 + (link1.link.length - link1.suffix!.length),
								text: link1.suffix!
							}
						}
					};
					const detectedLink2: ParsedLink = {
						prefix: link2.prefix ? {
							index: (detectedLink1.prefix?.index ?? detectedLink1.path.index) + link1.link.length + 1,
							text: link2.prefix
						} : undefined,
						path: {
							index: (detectedLink1.prefix?.index ?? detectedLink1.path.index) + link1.link.length + 1 + (link2.prefix ?? '').length,
							text: link2.link.replace(link2.suffix!, '').replace(link2.prefix ?? '', '')
						},
						suffix: {
							row: link2.hasRow ? testRow : undefined,
							col: link2.hasCol ? testCol : undefined,
							rowEnd: link2.hasRowEnd ? testRowEnd : undefined,
							colEnd: link2.hasColEnd ? testColEnd : undefined,
							suffix: {
								index: (detectedLink1.prefix?.index ?? detectedLink1.path.index) + link1.link.length + 1 + (link2.link.length - link2.suffix!.length),
								text: link2.suffix!
							}
						}
					};
					const detectedLink3: ParsedLink = {
						prefix: link3.prefix ? {
							index: (detectedLink2.prefix?.index ?? detectedLink2.path.index) + link2.link.length + 1,
							text: link3.prefix
						} : undefined,
						path: {
							index: (detectedLink2.prefix?.index ?? detectedLink2.path.index) + link2.link.length + 1 + (link3.prefix ?? '').length,
							text: link3.link.replace(link3.suffix!, '').replace(link3.prefix ?? '', '')
						},
						suffix: {
							row: link3.hasRow ? testRow : undefined,
							col: link3.hasCol ? testCol : undefined,
							rowEnd: link3.hasRowEnd ? testRowEnd : undefined,
							colEnd: link3.hasColEnd ? testColEnd : undefined,
							suffix: {
								index: (detectedLink2.prefix?.index ?? detectedLink2.path.index) + link2.link.length + 1 + (link3.link.length - link3.suffix!.length),
								text: link3.suffix!
							}
						}
					};
					expect(
						detectLinks(line, "posix")).toStrictEqual(
						[detectedLink1, detectedLink2, detectedLink3]
					);
				});
			}
		});
		it('should ignore links with suffixes when the path itself is the empty string', () => {
			expect(
				detectLinks('""",1', "posix")).toStrictEqual(
				[] as ParsedLink[]
			);
		});
	});
});
