import 'package:equatable/equatable.dart';

class PreviewEntryModel extends Equatable {
  const PreviewEntryModel({this.entry});

  final String? entry;

  factory PreviewEntryModel.fromJson(Map<String, dynamic> json) =>
      PreviewEntryModel(entry: (json['entry'] as String?)?.trim() ?? '');

  @override
  List<Object?> get props => [entry];
}

class PreviewModel extends Equatable {
  const PreviewModel({required this.entry, required this.url, required this.authenticated});

  final String entry;
  final String url;

  /// False for an external dev server, which must never receive the Operator
  /// Bearer token.
  final bool authenticated;

  @override
  List<Object?> get props => [entry, url, authenticated];
}
