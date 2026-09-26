import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

sealed class AttachmentLimits {
  static const int maxCount = 8;
  static const int maxBytes = 10 * 1024 * 1024;
  static const int maxTotalBytes = 25 * 1024 * 1024;
}

const String kSvgRefused = 'SVG files are not supported.';
const String kFileTooLarge = 'Each file must be under 10 MB.';
const String kTooManyFiles = 'You can attach up to 8 files.';
const String kTotalTooLarge = 'Attachments must add up to under 25 MB.';
const String kEmptyFile = 'Empty files are skipped.';

class AttachmentAdmission {
  const AttachmentAdmission({required this.accepted, this.notice});

  final List<ComposerAttachment> accepted;
  final String? notice;
}

bool isBlockedAttachment({required String name, required String mimeType}) =>
    mimeType.toLowerCase().trim() == 'image/svg+xml' || name.toLowerCase().trim().endsWith('.svg');

AttachmentAdmission admitAttachments(List<ComposerAttachment> current, List<ComposerAttachment> incoming) {
  final accepted = <ComposerAttachment>[];
  final notices = <String>{};
  final known = {for (final attachment in current) attachment.id};
  var count = current.length;
  var total = current.fold<int>(0, (sum, attachment) => sum + attachment.size);
  for (final attachment in incoming) {
    if (known.contains(attachment.id)) continue;
    if (isBlockedAttachment(name: attachment.name, mimeType: attachment.mimeType)) {
      notices.add(kSvgRefused);
      continue;
    }
    if (attachment.size == 0) {
      notices.add(kEmptyFile);
      continue;
    }
    if (attachment.size > AttachmentLimits.maxBytes) {
      notices.add(kFileTooLarge);
      continue;
    }
    if (count >= AttachmentLimits.maxCount) {
      notices.add(kTooManyFiles);
      continue;
    }
    if (total + attachment.size > AttachmentLimits.maxTotalBytes) {
      notices.add(kTotalTooLarge);
      continue;
    }
    accepted.add(attachment);
    known.add(attachment.id);
    count++;
    total += attachment.size;
  }
  return AttachmentAdmission(accepted: accepted, notice: notices.isEmpty ? null : notices.join(' '));
}

const Map<String, String> _mimeByExtension = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'log': 'text/plain',
  'zip': 'application/zip',
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

String attachmentMimeType(String name, String? reported) {
  final given = (reported ?? '').toLowerCase().trim();
  if (given.isNotEmpty && given != 'application/octet-stream') return given;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  return _mimeByExtension[name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
}
