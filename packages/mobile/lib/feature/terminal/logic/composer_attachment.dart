import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class ComposerAttachment extends Equatable {
  const ComposerAttachment({required this.id, required this.name, required this.mimeType, required this.bytes});

  final String id;
  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');

  int get size => bytes.length;

  @override
  List<Object?> get props => [id, name, mimeType, bytes.length];
}
