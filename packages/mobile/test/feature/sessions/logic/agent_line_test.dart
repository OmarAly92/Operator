import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/agent_line.dart';

void main() {
  const labels = {'default': 'Default', 'personal': 'Personal'};

  test('claude sessions name their account from the daemon labels', () {
    expect(sessionAccountLabel(const SessionModel(harness: 'claude-code', claudeAccountId: 'personal'), labels), 'Personal');
  });

  test('an omitted account is the default one', () {
    expect(sessionAccountLabel(const SessionModel(harness: 'claude-code'), labels), 'Default');
    expect(sessionAccountLabel(const SessionModel(harness: 'claude-code', claudeAccountId: ''), const {}), 'Default');
  });

  test('an unknown id falls back to a capitalised id', () {
    expect(sessionAccountLabel(const SessionModel(harness: 'claude-code', claudeAccountId: 'work'), const {}), 'Work');
  });

  test('other harnesses have no claude account', () {
    expect(sessionAccountLabel(const SessionModel(harness: 'codex', claudeAccountId: 'personal'), labels), isNull);
  });
}
