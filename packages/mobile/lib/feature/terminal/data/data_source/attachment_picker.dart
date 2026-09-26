import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:operator_mobile/feature/terminal/logic/attachment_limits.dart';
import 'package:operator_mobile/feature/terminal/logic/composer_attachment.dart';

class AttachmentPickFailure implements Exception {
  const AttachmentPickFailure(this.message);

  final String message;
}

class PickedAttachments {
  const PickedAttachments(this.attachments, {this.notice});

  static const PickedAttachments none = PickedAttachments([]);

  final List<ComposerAttachment> attachments;
  final String? notice;
}

abstract class AttachmentPicker {
  Future<PickedAttachments> camera();
  Future<PickedAttachments> photos({required int limit});
  Future<PickedAttachments> files();
}

class AttachmentPickerImp implements AttachmentPicker {
  AttachmentPickerImp(this._images, {Future<List<XFile>> Function()? pickFiles, int Function()? now})
    : _pickFiles = pickFiles ?? (() => openFiles()),
      _now = now ?? (() => DateTime.now().microsecondsSinceEpoch);

  static const double maxDimension = 2048;
  static const int quality = 85;

  final ImagePicker _images;
  final Future<List<XFile>> Function() _pickFiles;
  final int Function() _now;

  @override
  Future<PickedAttachments> camera() => _guard('Camera', () async {
    final shot = await _images.pickImage(
      source: ImageSource.camera,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
      requestFullMetadata: false,
    );
    return shot == null ? PickedAttachments.none : _readAll('camera', [shot]);
  });

  @override
  Future<PickedAttachments> photos({required int limit}) => _guard('Photos', () async {
    if (limit <= 0) return PickedAttachments.none;
    if (limit == 1) {
      final one = await _images.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: quality,
        requestFullMetadata: false,
      );
      return one == null ? PickedAttachments.none : _readAll('photo', [one]);
    }
    final picked = await _images.pickMultiImage(
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
      limit: limit,
      requestFullMetadata: false,
    );
    return _readAll('photo', picked);
  });

  @override
  Future<PickedAttachments> files() => _guard('Files', () async => _readAll('file', await _pickFiles()));

  Future<PickedAttachments> _readAll(String source, List<XFile> picked) async {
    final stamp = _now();
    final attachments = <ComposerAttachment>[];
    var refused = false;
    for (var i = 0; i < picked.length; i++) {
      if (await picked[i].length() > AttachmentLimits.maxBytes) {
        refused = true;
        continue;
      }
      attachments.add(
        ComposerAttachment(
          id: '$source:$stamp:$i',
          name: picked[i].name.isEmpty ? '$source-$i' : picked[i].name,
          mimeType: attachmentMimeType(picked[i].name, picked[i].mimeType),
          bytes: await picked[i].readAsBytes(),
        ),
      );
    }
    if (refused && attachments.isEmpty) throw const AttachmentPickFailure(kFileTooLarge);
    return PickedAttachments(attachments, notice: refused ? kFileTooLarge : null);
  }

  Future<PickedAttachments> _guard(String source, Future<PickedAttachments> Function() pick) async {
    try {
      return await pick();
    } on PlatformException catch (error) {
      throw AttachmentPickFailure(_pickMessage(source, error.code));
    }
  }
}

String _pickMessage(String source, String code) => switch (code) {
  'camera_access_denied' => 'Camera access is off. Turn it on in Settings to take a photo.',
  'photo_access_denied' => 'Photo access is off. Turn it on in Settings to attach photos.',
  _ => '$source is not available right now.',
};
