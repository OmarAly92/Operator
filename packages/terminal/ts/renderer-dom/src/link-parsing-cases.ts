/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

export interface ITestLink {
	link: string;
	prefix: string | undefined;
	suffix: string | undefined;
	// TODO: These has vars would be nicer as a flags enum
	hasRow: boolean;
	hasCol: boolean;
	hasRowEnd?: boolean;
	hasColEnd?: boolean;
}

export const testRow = 339;
export const testCol = 12;
export const testRowEnd = 341;
export const testColEnd = 789;
export const testLinks: ITestLink[] = [
	// Simple
	{ link: 'foo', prefix: undefined, suffix: undefined, hasRow: false, hasCol: false },
	{ link: 'foo:339', prefix: undefined, suffix: ':339', hasRow: true, hasCol: false },
	{ link: 'foo:339:12', prefix: undefined, suffix: ':339:12', hasRow: true, hasCol: true },
	{ link: 'foo:339:12-789', prefix: undefined, suffix: ':339:12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo:339.12', prefix: undefined, suffix: ':339.12', hasRow: true, hasCol: true },
	{ link: 'foo:339.12-789', prefix: undefined, suffix: ':339.12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo:339.12-341.789', prefix: undefined, suffix: ':339.12-341.789', hasRow: true, hasCol: true, hasRowEnd: true, hasColEnd: true },
	{ link: 'foo#339', prefix: undefined, suffix: '#339', hasRow: true, hasCol: false },
	{ link: 'foo#339:12', prefix: undefined, suffix: '#339:12', hasRow: true, hasCol: true },
	{ link: 'foo#339:12-789', prefix: undefined, suffix: '#339:12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo#339.12', prefix: undefined, suffix: '#339.12', hasRow: true, hasCol: true },
	{ link: 'foo#339.12-789', prefix: undefined, suffix: '#339.12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo#339.12-341.789', prefix: undefined, suffix: '#339.12-341.789', hasRow: true, hasCol: true, hasRowEnd: true, hasColEnd: true },
	{ link: 'foo 339', prefix: undefined, suffix: ' 339', hasRow: true, hasCol: false },
	{ link: 'foo 339:12', prefix: undefined, suffix: ' 339:12', hasRow: true, hasCol: true },
	{ link: 'foo 339:12-789', prefix: undefined, suffix: ' 339:12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo 339.12', prefix: undefined, suffix: ' 339.12', hasRow: true, hasCol: true },
	{ link: 'foo 339.12-789', prefix: undefined, suffix: ' 339.12-789', hasRow: true, hasCol: true, hasRowEnd: false, hasColEnd: true },
	{ link: 'foo 339.12-341.789', prefix: undefined, suffix: ' 339.12-341.789', hasRow: true, hasCol: true, hasRowEnd: true, hasColEnd: true },
	{ link: 'foo, 339', prefix: undefined, suffix: ', 339', hasRow: true, hasCol: false },

	// Double quotes
	{ link: '"foo",339', prefix: '"', suffix: '",339', hasRow: true, hasCol: false },
	{ link: '"foo",339:12', prefix: '"', suffix: '",339:12', hasRow: true, hasCol: true },
	{ link: '"foo",339.12', prefix: '"', suffix: '",339.12', hasRow: true, hasCol: true },
	{ link: '"foo", line 339', prefix: '"', suffix: '", line 339', hasRow: true, hasCol: false },
	{ link: '"foo", line 339, col 12', prefix: '"', suffix: '", line 339, col 12', hasRow: true, hasCol: true },
	{ link: '"foo", line 339, column 12', prefix: '"', suffix: '", line 339, column 12', hasRow: true, hasCol: true },
	{ link: '"foo":line 339', prefix: '"', suffix: '":line 339', hasRow: true, hasCol: false },
	{ link: '"foo":line 339, col 12', prefix: '"', suffix: '":line 339, col 12', hasRow: true, hasCol: true },
	{ link: '"foo":line 339, column 12', prefix: '"', suffix: '":line 339, column 12', hasRow: true, hasCol: true },
	{ link: '"foo": line 339', prefix: '"', suffix: '": line 339', hasRow: true, hasCol: false },
	{ link: '"foo": line 339, col 12', prefix: '"', suffix: '": line 339, col 12', hasRow: true, hasCol: true },
	{ link: '"foo": line 339, column 12', prefix: '"', suffix: '": line 339, column 12', hasRow: true, hasCol: true },
	{ link: '"foo" on line 339', prefix: '"', suffix: '" on line 339', hasRow: true, hasCol: false },
	{ link: '"foo" on line 339, col 12', prefix: '"', suffix: '" on line 339, col 12', hasRow: true, hasCol: true },
	{ link: '"foo" on line 339, column 12', prefix: '"', suffix: '" on line 339, column 12', hasRow: true, hasCol: true },
	{ link: '"foo" line 339', prefix: '"', suffix: '" line 339', hasRow: true, hasCol: false },
	{ link: '"foo" line 339 column 12', prefix: '"', suffix: '" line 339 column 12', hasRow: true, hasCol: true },

	// Single quotes
	{ link: '\'foo\',339', prefix: '\'', suffix: '\',339', hasRow: true, hasCol: false },
	{ link: '\'foo\',339:12', prefix: '\'', suffix: '\',339:12', hasRow: true, hasCol: true },
	{ link: '\'foo\',339.12', prefix: '\'', suffix: '\',339.12', hasRow: true, hasCol: true },
	{ link: '\'foo\', line 339', prefix: '\'', suffix: '\', line 339', hasRow: true, hasCol: false },
	{ link: '\'foo\', line 339, col 12', prefix: '\'', suffix: '\', line 339, col 12', hasRow: true, hasCol: true },
	{ link: '\'foo\', line 339, column 12', prefix: '\'', suffix: '\', line 339, column 12', hasRow: true, hasCol: true },
	{ link: '\'foo\':line 339', prefix: '\'', suffix: '\':line 339', hasRow: true, hasCol: false },
	{ link: '\'foo\':line 339, col 12', prefix: '\'', suffix: '\':line 339, col 12', hasRow: true, hasCol: true },
	{ link: '\'foo\':line 339, column 12', prefix: '\'', suffix: '\':line 339, column 12', hasRow: true, hasCol: true },
	{ link: '\'foo\': line 339', prefix: '\'', suffix: '\': line 339', hasRow: true, hasCol: false },
	{ link: '\'foo\': line 339, col 12', prefix: '\'', suffix: '\': line 339, col 12', hasRow: true, hasCol: true },
	{ link: '\'foo\': line 339, column 12', prefix: '\'', suffix: '\': line 339, column 12', hasRow: true, hasCol: true },
	{ link: '\'foo\' on line 339', prefix: '\'', suffix: '\' on line 339', hasRow: true, hasCol: false },
	{ link: '\'foo\' on line 339, col 12', prefix: '\'', suffix: '\' on line 339, col 12', hasRow: true, hasCol: true },
	{ link: '\'foo\' on line 339, column 12', prefix: '\'', suffix: '\' on line 339, column 12', hasRow: true, hasCol: true },
	{ link: '\'foo\' line 339', prefix: '\'', suffix: '\' line 339', hasRow: true, hasCol: false },
	{ link: '\'foo\' line 339 column 12', prefix: '\'', suffix: '\' line 339 column 12', hasRow: true, hasCol: true },

	// No quotes
	{ link: 'foo, line 339', prefix: undefined, suffix: ', line 339', hasRow: true, hasCol: false },
	{ link: 'foo, line 339, col 12', prefix: undefined, suffix: ', line 339, col 12', hasRow: true, hasCol: true },
	{ link: 'foo, line 339, column 12', prefix: undefined, suffix: ', line 339, column 12', hasRow: true, hasCol: true },
	{ link: 'foo:line 339', prefix: undefined, suffix: ':line 339', hasRow: true, hasCol: false },
	{ link: 'foo:line 339, col 12', prefix: undefined, suffix: ':line 339, col 12', hasRow: true, hasCol: true },
	{ link: 'foo:line 339, column 12', prefix: undefined, suffix: ':line 339, column 12', hasRow: true, hasCol: true },
	{ link: 'foo: line 339', prefix: undefined, suffix: ': line 339', hasRow: true, hasCol: false },
	{ link: 'foo: line 339, col 12', prefix: undefined, suffix: ': line 339, col 12', hasRow: true, hasCol: true },
	{ link: 'foo: line 339, column 12', prefix: undefined, suffix: ': line 339, column 12', hasRow: true, hasCol: true },
	{ link: 'foo on line 339', prefix: undefined, suffix: ' on line 339', hasRow: true, hasCol: false },
	{ link: 'foo on line 339, col 12', prefix: undefined, suffix: ' on line 339, col 12', hasRow: true, hasCol: true },
	{ link: 'foo on line 339, column 12', prefix: undefined, suffix: ' on line 339, column 12', hasRow: true, hasCol: true },
	{ link: 'foo line 339', prefix: undefined, suffix: ' line 339', hasRow: true, hasCol: false },
	{ link: 'foo line 339 column 12', prefix: undefined, suffix: ' line 339 column 12', hasRow: true, hasCol: true },

	// Parentheses
	{ link: 'foo(339)', prefix: undefined, suffix: '(339)', hasRow: true, hasCol: false },
	{ link: 'foo(339,12)', prefix: undefined, suffix: '(339,12)', hasRow: true, hasCol: true },
	{ link: 'foo(339, 12)', prefix: undefined, suffix: '(339, 12)', hasRow: true, hasCol: true },
	{ link: 'foo (339)', prefix: undefined, suffix: ' (339)', hasRow: true, hasCol: false },
	{ link: 'foo (339,12)', prefix: undefined, suffix: ' (339,12)', hasRow: true, hasCol: true },
	{ link: 'foo (339, 12)', prefix: undefined, suffix: ' (339, 12)', hasRow: true, hasCol: true },
	{ link: 'foo: (339)', prefix: undefined, suffix: ': (339)', hasRow: true, hasCol: false },
	{ link: 'foo: (339,12)', prefix: undefined, suffix: ': (339,12)', hasRow: true, hasCol: true },
	{ link: 'foo: (339, 12)', prefix: undefined, suffix: ': (339, 12)', hasRow: true, hasCol: true },
	{ link: 'foo(339:12)', prefix: undefined, suffix: '(339:12)', hasRow: true, hasCol: true },
	{ link: 'foo (339:12)', prefix: undefined, suffix: ' (339:12)', hasRow: true, hasCol: true },

	// Square brackets
	{ link: 'foo[339]', prefix: undefined, suffix: '[339]', hasRow: true, hasCol: false },
	{ link: 'foo[339,12]', prefix: undefined, suffix: '[339,12]', hasRow: true, hasCol: true },
	{ link: 'foo[339, 12]', prefix: undefined, suffix: '[339, 12]', hasRow: true, hasCol: true },
	{ link: 'foo [339]', prefix: undefined, suffix: ' [339]', hasRow: true, hasCol: false },
	{ link: 'foo [339,12]', prefix: undefined, suffix: ' [339,12]', hasRow: true, hasCol: true },
	{ link: 'foo [339, 12]', prefix: undefined, suffix: ' [339, 12]', hasRow: true, hasCol: true },
	{ link: 'foo: [339]', prefix: undefined, suffix: ': [339]', hasRow: true, hasCol: false },
	{ link: 'foo: [339,12]', prefix: undefined, suffix: ': [339,12]', hasRow: true, hasCol: true },
	{ link: 'foo: [339, 12]', prefix: undefined, suffix: ': [339, 12]', hasRow: true, hasCol: true },
	{ link: 'foo[339:12]', prefix: undefined, suffix: '[339:12]', hasRow: true, hasCol: true },
	{ link: 'foo [339:12]', prefix: undefined, suffix: ' [339:12]', hasRow: true, hasCol: true },

	// OCaml-style
	{ link: '"foo", line 339, character 12', prefix: '"', suffix: '", line 339, character 12', hasRow: true, hasCol: true },
	{ link: '"foo", line 339, characters 12-789', prefix: '"', suffix: '", line 339, characters 12-789', hasRow: true, hasCol: true, hasColEnd: true },
	{ link: '"foo", lines 339-341', prefix: '"', suffix: '", lines 339-341', hasRow: true, hasCol: false, hasRowEnd: true },
	{ link: '"foo", lines 339-341, characters 12-789', prefix: '"', suffix: '", lines 339-341, characters 12-789', hasRow: true, hasCol: true, hasRowEnd: true, hasColEnd: true },

	// Non-breaking space
	{ link: 'foo\u00A0339:12', prefix: undefined, suffix: '\u00A0339:12', hasRow: true, hasCol: true },
	{ link: '"foo" on line 339,\u00A0column 12', prefix: '"', suffix: '" on line 339,\u00A0column 12', hasRow: true, hasCol: true },
	{ link: '\'foo\' on line\u00A0339, column 12', prefix: '\'', suffix: '\' on line\u00A0339, column 12', hasRow: true, hasCol: true },
	{ link: 'foo (339,\u00A012)', prefix: undefined, suffix: ' (339,\u00A012)', hasRow: true, hasCol: true },
	{ link: 'foo\u00A0[339, 12]', prefix: undefined, suffix: '\u00A0[339, 12]', hasRow: true, hasCol: true },
];
export const testLinksWithSuffix = testLinks.filter(e => !!e.suffix);
