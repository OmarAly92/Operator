/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import { describe, expect, it } from "vitest";
import { detectLinks, detectLinkSuffixes, getLinkSuffix, type LinkOs, type ParsedLink, removeLinkQueryString, removeLinkSuffix } from "./link-parsing";
import { testCol, testColEnd, testLinks, testRow, testRowEnd } from "./link-parsing-cases";

const operatingSystems: ReadonlyArray<LinkOs> = ["posix", "windows"];
const osTestPath: Record<LinkOs, string> = { posix: "/test/path/linux", windows: "C:\\test\\path\\windows" };
const osLabel: Record<LinkOs, string> = { posix: "[posix]", windows: "[Windows]" };

describe('TerminalLinkParsing', () => {
	describe('removeLinkSuffix', () => {
		for (const testLink of testLinks) {
			it('`' + testLink.link + '`', () => {
				expect(
					removeLinkSuffix(testLink.link)).toStrictEqual(
					testLink.suffix === undefined ? testLink.link : testLink.link.replace(testLink.suffix, '')
				);
			});
		}
	});
	describe('getLinkSuffix', () => {
		for (const testLink of testLinks) {
			it('`' + testLink.link + '`', () => {
				expect(
					getLinkSuffix(testLink.link)).toStrictEqual(
					testLink.suffix === undefined ? null : {
						row: testLink.hasRow ? testRow : undefined,
						col: testLink.hasCol ? testCol : undefined,
						rowEnd: testLink.hasRowEnd ? testRowEnd : undefined,
						colEnd: testLink.hasColEnd ? testColEnd : undefined,
						suffix: {
							index: testLink.link.length - testLink.suffix.length,
							text: testLink.suffix
						}
					} as ReturnType<typeof getLinkSuffix>
				);
			});
		}
	});
	describe('detectLinkSuffixes', () => {
		for (const testLink of testLinks) {
			it('`' + testLink.link + '`', () => {
				expect(
					detectLinkSuffixes(testLink.link)).toStrictEqual(
					testLink.suffix === undefined ? [] : [{
						row: testLink.hasRow ? testRow : undefined,
						col: testLink.hasCol ? testCol : undefined,
						rowEnd: testLink.hasRowEnd ? testRowEnd : undefined,
						colEnd: testLink.hasColEnd ? testColEnd : undefined,
						suffix: {
							index: testLink.link.length - testLink.suffix.length,
							text: testLink.suffix
						}
					} as ReturnType<typeof getLinkSuffix>]
				);
			});
		}

		it('foo(1, 2) bar[3, 4] baz on line 5', () => {
			expect(
				detectLinkSuffixes('foo(1, 2) bar[3, 4] baz on line 5')).toStrictEqual(
				[
					{
						col: 2,
						row: 1,
						rowEnd: undefined,
						colEnd: undefined,
						suffix: {
							index: 3,
							text: '(1, 2)'
						}
					},
					{
						col: 4,
						row: 3,
						rowEnd: undefined,
						colEnd: undefined,
						suffix: {
							index: 13,
							text: '[3, 4]'
						}
					},
					{
						col: undefined,
						row: 5,
						rowEnd: undefined,
						colEnd: undefined,
						suffix: {
							index: 23,
							text: ' on line 5'
						}
					}
				]
			);
		});
	});
	describe('removeLinkQueryString', () => {
		it('should remove any query string from the link', () => {
			expect(removeLinkQueryString('?a=b')).toBe( '');
			expect(removeLinkQueryString('foo?a=b')).toBe( 'foo');
			expect(removeLinkQueryString('./foo?a=b')).toBe( './foo');
			expect(removeLinkQueryString('/foo/bar?a=b')).toBe( '/foo/bar');
			expect(removeLinkQueryString('foo?a=b?')).toBe( 'foo');
			expect(removeLinkQueryString('foo?a=b&c=d')).toBe( 'foo');
		});
		it('should respect ? in UNC paths', () => {
			expect(removeLinkQueryString('\\\\?\\foo?a=b')).toBe( '\\\\?\\foo');
		});
	});
	describe('detectLinks', () => {
		it('foo(1, 2) bar[3, 4] "baz" on line 5', () => {
			expect(
				detectLinks('foo(1, 2) bar[3, 4] "baz" on line 5', "posix")).toStrictEqual(
				[
					{
						path: {
							index: 0,
							text: 'foo'
						},
						prefix: undefined,
						suffix: {
							col: 2,
							row: 1,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 3,
								text: '(1, 2)'
							}
						}
					},
					{
						path: {
							index: 10,
							text: 'bar'
						},
						prefix: undefined,
						suffix: {
							col: 4,
							row: 3,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 13,
								text: '[3, 4]'
							}
						}
					},
					{
						path: {
							index: 21,
							text: 'baz'
						},
						prefix: {
							index: 20,
							text: '"'
						},
						suffix: {
							col: undefined,
							row: 5,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 24,
								text: '" on line 5'
							}
						}
					}
				] as ParsedLink[]
			);
		});

		it('should detect multiple links when opening brackets are in the text', () => {
			expect(
				detectLinks('notlink[foo:45]', "posix")).toStrictEqual(
				[
					{
						path: {
							index: 0,
							text: 'notlink[foo'
						},
						prefix: undefined,
						suffix: {
							col: undefined,
							row: 45,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 11,
								text: ':45'
							}
						}
					},
					{
						path: {
							index: 8,
							text: 'foo'
						},
						prefix: undefined,
						suffix: {
							col: undefined,
							row: 45,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 11,
								text: ':45'
							}
						}
					},
				] as ParsedLink[]
			);
		});

		it('should extract the link prefix', () => {
			expect(
				detectLinks('"foo", line 5, col 6', "posix")).toStrictEqual(
				[
					{
						path: {
							index: 1,
							text: 'foo'
						},
						prefix: {
							index: 0,
							text: '"',
						},
						suffix: {
							row: 5,
							col: 6,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 4,
								text: '", line 5, col 6'
							}
						}
					},
				] as ParsedLink[]
			);
		});

		it('should be smart about determining the link prefix when multiple prefix characters exist', () => {
			expect(
				detectLinks('echo \'"foo", line 5, col 6\'', "posix"),
				'The outer single quotes should be excluded from the link prefix and suffix'
			).toStrictEqual(
				[
					{
						path: {
							index: 7,
							text: 'foo'
						},
						prefix: {
							index: 6,
							text: '"',
						},
						suffix: {
							row: 5,
							col: 6,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 10,
								text: '", line 5, col 6'
							}
						}
					},
				] as ParsedLink[]);
		});

		it('should detect both suffix and non-suffix links on a single line', () => {
			expect(
				detectLinks('PS C:\\Github\\microsoft\\vscode> echo \'"foo", line 5, col 6\'', "windows")).toStrictEqual(
				[
					{
						path: {
							index: 3,
							text: 'C:\\Github\\microsoft\\vscode'
						},
						prefix: undefined,
						suffix: undefined
					},
					{
						path: {
							index: 38,
							text: 'foo'
						},
						prefix: {
							index: 37,
							text: '"',
						},
						suffix: {
							row: 5,
							col: 6,
							rowEnd: undefined,
							colEnd: undefined,
							suffix: {
								index: 41,
								text: '", line 5, col 6'
							}
						}
					}
				] as ParsedLink[]
			);
		});

		describe('"|"', () => {
			it('should exclude pipe characters from link paths', () => {
				expect(
					detectLinks('|C:\\Github\\microsoft\\vscode|', "windows")).toStrictEqual(
					[
						{
							path: {
								index: 1,
								text: 'C:\\Github\\microsoft\\vscode'
							},
							prefix: undefined,
							suffix: undefined
						}
					] as ParsedLink[]
				);
			});
			it('should exclude pipe characters from link paths with suffixes', () => {
				expect(
					detectLinks('|C:\\Github\\microsoft\\vscode:400|', "windows")).toStrictEqual(
					[
						{
							path: {
								index: 1,
								text: 'C:\\Github\\microsoft\\vscode'
							},
							prefix: undefined,
							suffix: {
								col: undefined,
								row: 400,
								rowEnd: undefined,
								colEnd: undefined,
								suffix: {
									index: 27,
									text: ':400'
								}
							}
						}
					] as ParsedLink[]
				);
			});
		});

		describe('"<>"', () => {
			for (const os of operatingSystems) {
				it(`should exclude bracket characters from link paths ${osLabel[os]}`, () => {
					expect(
						detectLinks(`<${osTestPath[os]}<`, os)).toStrictEqual(
						[
							{
								path: {
									index: 1,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
					expect(
						detectLinks(`>${osTestPath[os]}>`, os)).toStrictEqual(
						[
							{
								path: {
									index: 1,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
				});
				it(`should exclude bracket characters from link paths with suffixes ${osLabel[os]}`, () => {
					expect(
						detectLinks(`<${osTestPath[os]}:400<`, os)).toStrictEqual(
						[
							{
								path: {
									index: 1,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: {
									col: undefined,
									row: 400,
									rowEnd: undefined,
									colEnd: undefined,
									suffix: {
										index: 1 + osTestPath[os].length,
										text: ':400'
									}
								}
							}
						] as ParsedLink[]
					);
					expect(
						detectLinks(`>${osTestPath[os]}:400>`, os)).toStrictEqual(
						[
							{
								path: {
									index: 1,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: {
									col: undefined,
									row: 400,
									rowEnd: undefined,
									colEnd: undefined,
									suffix: {
										index: 1 + osTestPath[os].length,
										text: ':400'
									}
								}
							}
						] as ParsedLink[]
					);
				});
			}
		});

		describe('query strings', () => {
			for (const os of operatingSystems) {
				it(`should exclude query strings from link paths ${osLabel[os]}`, () => {
					expect(
						detectLinks(`${osTestPath[os]}?a=b`, os)).toStrictEqual(
						[
							{
								path: {
									index: 0,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
					expect(
						detectLinks(`${osTestPath[os]}?a=b&c=d`, os)).toStrictEqual(
						[
							{
								path: {
									index: 0,
									text: osTestPath[os]
								},
								prefix: undefined,
								suffix: undefined
							}
						] as ParsedLink[]
					);
				});
				it('should not detect links starting with ? within query strings that contain posix-style paths (#204195)', () => {
					// ? appended to the cwd will exist since it's just the cwd
					expect(detectLinks(`http://foo.com/?bar=/a/b&baz=c`, os).some(e => e.path.text.startsWith('?'))).toBe( false);
				});
				it('should not detect links starting with ? within query strings that contain Windows-style paths (#204195)', () => {
					// ? appended to the cwd will exist since it's just the cwd
					expect(detectLinks(`http://foo.com/?bar=a:\\b&baz=c`, os).some(e => e.path.text.startsWith('?'))).toBe( false);
				});
			}
		});
	});
});
