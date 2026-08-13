import 'package:equatable/equatable.dart';

class SessionPrSummaryModel extends Equatable {
  const SessionPrSummaryModel({
    this.url,
    this.htmlUrl,
    this.number,
    this.title,
    this.state,
    this.repo,
    this.author,
    this.sourceBranch,
    this.targetBranch,
    this.additions,
    this.deletions,
    this.changedFiles,
    this.ciState,
    this.failingChecks = const [],
    this.reviewDecision,
    this.hasUnresolvedHumanComments,
    this.mergeabilityState,
    this.mergeReasons = const [],
    this.updatedAt,
  });

  final String? url;
  final String? htmlUrl;
  final int? number;
  final String? title;
  final String? state;
  final String? repo;
  final String? author;
  final String? sourceBranch;
  final String? targetBranch;
  final int? additions;
  final int? deletions;
  final int? changedFiles;
  final String? ciState;
  final List<String> failingChecks;
  final String? reviewDecision;
  final bool? hasUnresolvedHumanComments;
  final String? mergeabilityState;
  final List<String> mergeReasons;
  final String? updatedAt;

  factory SessionPrSummaryModel.fromJson(Map<String, dynamic> json) {
    final ci = json['ci'] as Map<String, dynamic>?;
    final review = json['review'] as Map<String, dynamic>?;
    final mergeability = json['mergeability'] as Map<String, dynamic>?;
    return SessionPrSummaryModel(
      url: json['url'] as String?,
      htmlUrl: json['htmlUrl'] as String?,
      number: json['number'] as int?,
      title: json['title'] as String?,
      state: json['state'] as String?,
      repo: json['repo'] as String?,
      author: json['author'] as String?,
      sourceBranch: json['sourceBranch'] as String?,
      targetBranch: json['targetBranch'] as String?,
      additions: json['additions'] as int?,
      deletions: json['deletions'] as int?,
      changedFiles: json['changedFiles'] as int?,
      ciState: ci?['state'] as String?,
      failingChecks: (ci?['failingChecks'] as List<dynamic>? ?? const [])
          .map((c) => (c as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      reviewDecision: review?['decision'] as String?,
      hasUnresolvedHumanComments: review?['hasUnresolvedHumanComments'] as bool?,
      mergeabilityState: mergeability?['state'] as String?,
      mergeReasons: (mergeability?['reasons'] as List<dynamic>? ?? const []).cast<String>(),
      updatedAt: json['updatedAt'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    url, htmlUrl, number, title, state, repo, author, sourceBranch, targetBranch, additions,
    deletions, changedFiles, ciState, failingChecks, reviewDecision, hasUnresolvedHumanComments,
    mergeabilityState, mergeReasons, updatedAt,
  ];
}
