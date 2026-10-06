import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

ComposerAttachment file(String id, int size, {String? name, String mimeType = 'image/png'}) =>
    ComposerAttachment(id: id, name: name ?? '$id.png', mimeType: mimeType, bytes: Uint8List(size));

void main() {
  test('admission refuses oversize, overflow, over-count and svg but keeps the rest', () {
    final current = [for (var i = 0; i < 6; i++) file('c$i', 1024)];
    final admission = admitAttachments(current, [
      file('big', AttachmentLimits.maxBytes + 1),
      file('vector', 10, name: 'logo.svg', mimeType: 'application/octet-stream'),
      file('mime-svg', 10, mimeType: 'image/svg+xml'),
      file('ok-1', 1024),
      file('ok-2', 1024),
      file('ninth', 1024),
    ]);

    expect(admission.accepted.map((a) => a.id), ['ok-1', 'ok-2']);
    expect(admission.notice, contains(kFileTooLarge));
    expect(admission.notice, contains(kSvgRefused));
    expect(admission.notice, contains(kTooManyFiles));
  });

  test('the running total may not pass 25 MB', () {
    final nine = AttachmentLimits.maxBytes - 1;
    final admission = admitAttachments([file('a', nine), file('b', nine)], [file('c', nine)]);

    expect(admission.accepted, isEmpty);
    expect(admission.notice, kTotalTooLarge);
  });

  test('a file exactly at the per-file cap is accepted', () {
    final admission = admitAttachments(const [], [file('edge', AttachmentLimits.maxBytes)]);
    expect(admission.accepted.single.id, 'edge');
    expect(admission.notice, isNull);
  });

  test('an empty file and a duplicate are dropped', () {
    final admission = admitAttachments([file('same', 10)], [file('same', 10), file('empty', 0)]);
    expect(admission.accepted, isEmpty);
    expect(admission.notice, kEmptyFile);
  });

  test('the mime type falls back to the extension', () {
    expect(attachmentMimeType('scan.PDF', null), 'application/pdf');
    expect(attachmentMimeType('IMG_0001.HEIC', ''), 'image/heic');
    expect(attachmentMimeType('notes.md', 'application/octet-stream'), 'text/markdown');
    expect(attachmentMimeType('photo.jpg', 'image/jpeg'), 'image/jpeg');
    expect(attachmentMimeType('README', null), 'application/octet-stream');
  });

  test('text and code files get a type the daemon turns back into their extension', () {
    const expected = {
      'md': 'text/markdown',
      'txt': 'text/plain',
      'json': 'application/json',
      'yaml': 'application/yaml',
      'yml': 'application/yaml',
      'toml': 'application/toml',
      'dart': 'text/x-dart',
      'go': 'text/x-go',
      'ts': 'text/typescript',
      'tsx': 'text/tsx',
      'js': 'text/javascript',
      'py': 'text/x-python',
      'rb': 'text/x-ruby',
      'rs': 'text/x-rust',
      'swift': 'text/x-swift',
      'kt': 'text/x-kotlin',
      'java': 'text/x-java',
      'sh': 'application/x-sh',
      'sql': 'application/sql',
      'csv': 'text/csv',
      'xml': 'application/xml',
      'html': 'text/html',
      'css': 'text/css',
    };
    for (final entry in expected.entries) {
      expect(attachmentMimeType('file.${entry.key}', null), entry.value, reason: entry.key);
    }
  });

  test('an svg is blocked by name or by type', () {
    expect(isBlockedAttachment(name: 'a.SVG', mimeType: 'application/octet-stream'), isTrue);
    expect(isBlockedAttachment(name: 'a', mimeType: 'image/svg+xml'), isTrue);
    expect(isBlockedAttachment(name: 'a.png', mimeType: 'image/png'), isFalse);
  });
}
