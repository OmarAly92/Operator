import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/pickers/picker_filter.dart';

void main() {
  test('an empty or blank query matches everything', () {
    expect(PickerFilter.matches('', ['x']), isTrue);
    expect(PickerFilter.matches('   ', [null]), isTrue);
  });

  test('matches a case-insensitive substring of any field, ignoring nulls', () {
    expect(PickerFilter.matches('OPER', ['Operator', null]), isTrue);
    expect(PickerFilter.matches('ops', [null, 'devops']), isTrue);
    expect(PickerFilter.matches(' tor ', ['Operator']), isTrue);
    expect(PickerFilter.matches('zzz', ['Operator', 'op']), isFalse);
  });
}
