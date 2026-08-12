import 'package:equatable/equatable.dart';

class SessionPrModel extends Equatable {
  const SessionPrModel({
    this.url,
    this.number,
    this.state,
    this.ci,
    this.review,
    this.mergeable,
    this.reviewComments,
  });

  final String? url;
  final int? number;
  final String? state;
  final String? ci;
  final String? review;
  final bool? mergeable;
  final bool? reviewComments;

  factory SessionPrModel.fromJson(Map<String, dynamic> json) => SessionPrModel(
    url: json['url'] as String?,
    number: json['number'] as int?,
    state: json['state'] as String?,
    ci: json['ci'] as String?,
    review: json['review'] as String?,
    mergeable: json['mergeability'] == 'mergeable',
    reviewComments: json['reviewComments'] as bool?,
  );

  @override
  List<Object?> get props => [url, number, state, ci, review, mergeable, reviewComments];
}
