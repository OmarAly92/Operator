import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart'
    show XFile, XTypeGroup, openFiles;
import 'package:image_picker/image_picker.dart' show ImagePicker;
import 'package:operator_mobile/feature/chat/data/model/chat_attachment_model.dart';

const int kMaxAttachments = 8;
const int kMaxImageBytes = 10 * 1024 * 1024;
const int kMaxImageBytesTotal = 25 * 1024 * 1024;
const int kMaxEmbeddedFileBytes = 500000;
const Set<String> kSupportedImageTypes = {
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/gif',
  'image/webp',
  'image/bmp',
};

class AttachmentPickerException implements Exception {
  const AttachmentPickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedAttachment extends Equatable {
  const PickedAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    this.image,
    this.resource,
  });

  final String id;
  final String name;
  final int bytes;
  final ChatImageModel? image;
  final ChatResourceModel? resource;

  bool get isImage => image != null;

  @override
  List<Object?> get props => [id, name, bytes, image, resource];
}

abstract class AttachmentPicker {
  Future<List<PickedAttachment>> pickImages();

  Future<List<PickedAttachment>> pickTextFiles();
}

Future<PickedAttachment> imageAttachmentFromFile(XFile asset) async {
  final mimeType = (asset.mimeType ?? 'image/jpeg').toLowerCase();
  if (!kSupportedImageTypes.contains(mimeType)) {
    throw const AttachmentPickerException(
      'Only PNG, JPEG, GIF, WebP, and BMP images are supported.',
    );
  }
  final declaredBytes = await asset.length();
  if (declaredBytes > kMaxImageBytes) {
    throw const AttachmentPickerException('Each image must be under 10 MB.');
  }
  final bytes = await asset.readAsBytes();
  if (bytes.length > kMaxImageBytes) {
    throw const AttachmentPickerException('Each image must be under 10 MB.');
  }
  return PickedAttachment(
    id: '${asset.path}-${DateTime.now().microsecondsSinceEpoch}',
    name: asset.name.isEmpty ? 'Image' : asset.name,
    bytes: bytes.length,
    image: ChatImageModel(mimeType: mimeType, data: base64Encode(bytes)),
  );
}

Future<PickedAttachment> textAttachmentFromFile(XFile file) async {
  final declaredBytes = await file.length();
  if (declaredBytes > kMaxEmbeddedFileBytes) {
    throw _embeddedFileTooLarge(file.name);
  }
  final body = await file.readAsString();
  final bytes = utf8.encode(body).length;
  if (bytes > kMaxEmbeddedFileBytes) {
    throw _embeddedFileTooLarge(file.name);
  }
  return PickedAttachment(
    id: '${file.path}-${DateTime.now().microsecondsSinceEpoch}',
    name: file.name,
    bytes: bytes,
    resource: ChatResourceModel(
      uri: 'mobile-attachment://${Uri.encodeComponent(file.name)}',
      name: file.name,
      mimeType: file.mimeType ?? 'text/plain',
      text: body,
    ),
  );
}

AttachmentPickerException _embeddedFileTooLarge(String name) =>
    AttachmentPickerException(
      '$name is larger than 500 KB. Reference a worktree file with @ instead.',
    );

class PlatformAttachmentPicker implements AttachmentPicker {
  PlatformAttachmentPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<PickedAttachment>> pickImages() async {
    final assets = await _imagePicker.pickMultiImage(
      imageQuality: 82,
      limit: 4,
    );
    final picked = <PickedAttachment>[];

    for (final asset in assets) {
      picked.add(await imageAttachmentFromFile(asset));
    }
    return picked;
  }

  @override
  Future<List<PickedAttachment>> pickTextFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'text',
          mimeTypes: [
            'text/*',
            'application/json',
            'application/xml',
            'application/yaml',
          ],
          uniformTypeIdentifiers: [
            'public.plain-text',
            'public.json',
            'public.xml',
            'public.source-code',
          ],
        ),
      ],
    );

    final picked = <PickedAttachment>[];
    for (final file in files) {
      picked.add(await textAttachmentFromFile(file));
    }
    return picked;
  }
}
