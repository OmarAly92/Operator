import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';

const String kNewBranchLabel = 'New branch';
const String kDetachedHeadLabel = 'Detached HEAD';
const String kBranchesFailedText = "Couldn't load branches";
const String kSearchBranchesHint = 'Search branches';
const String kNoBranchMatchesText = 'No matching branches';
const int kBranchSearchThreshold = 10;

const String kBranchCheckedOutElsewhere = 'BRANCH_CHECKED_OUT_ELSEWHERE';
const String kBranchNotCheckedOut = 'BRANCH_NOT_CHECKED_OUT';

sealed class BranchOptions {
  static String rowValue({
    required bool useWorktree,
    required String? selected,
    required String current,
    required bool loading,
    required bool failed,
  }) {
    if (useWorktree) return selected ?? kNewBranchLabel;
    if (loading) return 'Loading…';
    if (failed) return 'Unknown';
    return current.isEmpty ? kDetachedHeadLabel : current;
  }

  static String? busyReason(ProjectBranchModel branch) {
    if (!branch.isBusy) return null;
    if (branch.isMainCheckout == true) return 'Checked out in your project folder — turn off worktree to work on it';
    return 'In use by ${folderName(branch.checkedOutAt!)}';
  }

  static String folderName(String path) {
    final parts = path.split(RegExp(r'[/\\]+')).where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  static bool showsSearch(List<ProjectBranchModel> branches) => branches.length > kBranchSearchThreshold;

  static List<ProjectBranchModel> filter(List<ProjectBranchModel> branches, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return branches;
    return branches.where((branch) => (branch.name ?? '').toLowerCase().contains(needle)).toList();
  }

  static String spawnFailureMessage(Failure failure) => switch (failure.apiStatus) {
    kBranchCheckedOutElsewhere => 'That branch is checked out somewhere else. Pick another branch or New branch.',
    kBranchNotCheckedOut => 'The project folder is on a different branch now. Reopen this screen and try again.',
    _ => failure.message,
  };
}
