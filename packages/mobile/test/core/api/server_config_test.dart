import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('builds an http base from host and port', () {
      const config = ServerConfig(
        host: '100.101.102.103',
        httpPort: '3011',
        secure: false,
        password: 'secret12',
      );

      expect(config.httpBase, 'http://100.101.102.103:3011');
      expect(config.wsBase, 'ws://100.101.102.103:3011');
    });

    test('switches scheme when secure', () {
      const config = ServerConfig(
        host: 'my-pc.tail1234.ts.net',
        httpPort: '443',
        secure: true,
        password: 'secret12',
      );

      expect(config.httpBase, 'https://my-pc.tail1234.ts.net:443');
      expect(config.wsBase, 'wss://my-pc.tail1234.ts.net:443');
    });
  });
}
