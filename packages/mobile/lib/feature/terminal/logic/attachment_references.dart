const String kAttachedFilesHeader = 'Attached files (read these files in the workspace for context):';

String appendAttachmentReferences(String message, List<String> paths) {
  if (paths.isEmpty) return message;
  final buffer = StringBuffer();
  if (message.trim().isNotEmpty) {
    buffer
      ..write(message)
      ..write('\n\n');
  }
  buffer.write(kAttachedFilesHeader);
  for (final path in paths) {
    buffer
      ..write('\n- ')
      ..write(path);
  }
  return buffer.toString();
}
