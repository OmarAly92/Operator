import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';
import 'package:operator_mobile/feature/spawn/logic/branch_options.dart';

void main() {
  group('rowValue', () {
    test('with a worktree shows the picked branch or New branch', () {
      expect(
        BranchOptions.rowValue(useWorktree: true, selected: null, current: 'main', loading: false, failed: false),
        'New branch',
      );
      expect(
        BranchOptions.rowValue(useWorktree: true, selected: 'feat/x', current: 'main', loading: false, failed: false),
        'feat/x',
      );
    });

    test('without a worktree shows the current branch or Detached HEAD', () {
      expect(
        BranchOptions.rowValue(useWorktree: false, selected: 'feat/x', current: 'main', loading: false, failed: false),
        'main',
      );
      expect(
        BranchOptions.rowValue(useWorktree: false, selected: null, current: '', loading: false, failed: false),
        'Detached HEAD',
      );
    });
  });

  test('busyReason names the project folder or the worktree folder', () {
    expect(BranchOptions.busyReason(const ProjectBranchModel(name: 'main')), isNull);
    expect(
      BranchOptions.busyReason(
        const ProjectBranchModel(name: 'logic/home', checkedOutAt: '/Users/me/rafeeq', isMainCheckout: true),
      ),
      'Checked out in your project folder — turn off worktree to work on it',
    );
    expect(
      BranchOptions.busyReason(
        const ProjectBranchModel(name: 'feat/x', checkedOutAt: '/Users/me/.worktrees/rafeeq-3/', isMainCheckout: false),
      ),
      'In use by rafeeq-3',
    );
  });

  test('filter matches a case-insensitive substring and keeps order', () {
    const branches = [
      ProjectBranchModel(name: 'Feat/Login'),
      ProjectBranchModel(name: 'main'),
      ProjectBranchModel(name: 'fix/login-flake'),
    ];

    expect(BranchOptions.filter(branches, 'LOGIN').map((b) => b.name), ['Feat/Login', 'fix/login-flake']);
    expect(BranchOptions.filter(branches, '  '), branches);
  });

  test('search shows only above ten branches', () {
    expect(BranchOptions.showsSearch(List.filled(10, const ProjectBranchModel(name: 'b'))), isFalse);
    expect(BranchOptions.showsSearch(List.filled(11, const ProjectBranchModel(name: 'b'))), isTrue);
  });

  test('spawnFailureMessage explains the two branch codes and passes others through', () {
    expect(
      BranchOptions.spawnFailureMessage(
        ServerFailure(error: 'x', message: 'raw', apiStatus: 'BRANCH_CHECKED_OUT_ELSEWHERE'),
      ),
      'That branch is checked out somewhere else. Pick another branch or New branch.',
    );
    expect(
      BranchOptions.spawnFailureMessage(ServerFailure(error: 'x', message: 'raw', apiStatus: 'BRANCH_NOT_CHECKED_OUT')),
      'The project folder is on a different branch now. Reopen this screen and try again.',
    );
    expect(BranchOptions.spawnFailureMessage(ServerFailure(error: 'x', message: 'boom', apiStatus: 'OTHER')), 'boom');
  });
}
