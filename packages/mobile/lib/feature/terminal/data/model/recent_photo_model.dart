import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class RecentPhotoModel extends Equatable {
  const RecentPhotoModel({this.id, this.thumbnail});

  final String? id;
  final Uint8List? thumbnail;

  @override
  List<Object?> get props => [id, thumbnail?.length];
}
