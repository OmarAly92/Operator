import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branches_model.dart';

void main() {
  test('parses current and branches in daemon order', () {
    final model = ProjectBranchesModel.fromJson({
      'current': 'logic/home',
      'branches': [
        {'name': 'logic/home', 'checkedOutAt': '/Users/me/rafeeq', 'isMainCheckout': true},
        {'name': 'feat/x', 'checkedOutAt': '/Users/me/.worktrees/rafeeq-3', 'isMainCheckout': false},
        {'name': 'main', 'isMainCheckout': false},
      ],
    });

    expect(model.current, 'logic/home');
    expect(model.branches!.map((b) => b.name), ['logic/home', 'feat/x', 'main']);
    expect(model.branches!.first.isMainCheckout, isTrue);
    expect(model.branches![1].checkedOutAt, '/Users/me/.worktrees/rafeeq-3');
  });

  test('a free branch has no checkedOutAt and is not busy', () {
    final branch = ProjectBranchModel.fromJson({'name': 'main', 'isMainCheckout': false});

    expect(branch.checkedOutAt, isNull);
    expect(branch.isBusy, isFalse);
    expect(const ProjectBranchModel(name: 'x', checkedOutAt: '/a').isBusy, isTrue);
  });

  test('a detached HEAD reports an empty current', () {
    final model = ProjectBranchesModel.fromJson({'current': '', 'branches': <dynamic>[]});

    expect(model.current, '');
    expect(model.branches, isEmpty);
  });

  test('tolerates a body without branches', () {
    final model = ProjectBranchesModel.fromJson(const {});

    expect(model.current, isNull);
    expect(model.branches, isNull);
  });
}
