import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class StageSessionAttachmentsParams extends Equatable {
  const StageSessionAttachmentsParams({required this.files});

  final List<ComposerAttachment> files;

  Map<String, dynamic> toJson() => {
    'attachments': [
      for (final file in files) {'mimeType': file.mimeType, 'data': base64Encode(file.bytes)},
    ],
  };

  @override
  List<Object?> get props => [files];
}
