import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/blocks/data/model/block_event_model.dart';
import 'package:operator_mobile/feature/blocks/logic/command_confirmation.dart';

BlockEventModel _event({String? kind}) => BlockEventModel(kind: kind);

void main() {
  test('a compaction event confirms compact', () {
    expect(confirmsCommand('compact', _event(kind: 'compaction')), isTrue);
  });

  test('a turn_model event confirms model', () {
    expect(confirmsCommand('model', _event(kind: 'turn_model')), isTrue);
  });

  test('a compaction event does not confirm model', () {
    expect(confirmsCommand('model', _event(kind: 'compaction')), isFalse);
  });

  test('an assistant_text event confirms nothing', () {
    for (final command in ['stop', 'compact', 'model']) {
      expect(confirmsCommand(command, _event(kind: 'assistant_text')), isFalse);
    }
  });

  test('stop is confirmed by the session going idle, not by a block event', () {
    expect(confirmsCommand('stop', _event(kind: 'stop')), isFalse);
    expect(confirmsStop('idle'), isTrue);
    expect(confirmsStop('active'), isFalse);
    expect(confirmsStop(null), isFalse);
  });
}
