import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/feature/usage/data/model/params/usage_rollup_params.dart';

void main() {
  group('UsageRollupParams', () {
    test('omits days from the query map when null rather than sending the literal string "null"', () {
      const params = UsageRollupParams(bucket: 'day');
      expect(params.toJson(), {'bucket': 'day'});
      expect(params.toJson().containsKey('days'), isFalse);
    });

    test('includes days when set', () {
      const params = UsageRollupParams(bucket: 'week', days: 30);
      expect(params.toJson(), {'bucket': 'week', 'days': 30});
    });
  });
}
