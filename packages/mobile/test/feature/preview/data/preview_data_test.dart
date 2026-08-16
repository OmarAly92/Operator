import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/end_points.dart';
import 'package:operator_mobile/core/api/models/global_response.dart';
import 'package:operator_mobile/core/api/server_config.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/model/preview_model.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';

class _MockApiConsumer extends Mock implements ApiConsumer {}

class _MockDataSource extends Mock implements PreviewRemoteDataSource {}

class _MockNetworkStatus extends Mock implements NetworkStatus {}

class _MockConfigStore extends Mock implements ServerConfigStore {}

Response<dynamic> _response(Object? data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: '/'), data: data);

void main() {
  group('data source', () {
    test('reads the entry the detector found', () async {
      final apiConsumer = _MockApiConsumer();
      when(() => apiConsumer.get(any())).thenAnswer(
        (_) async => _response({'entry': ' dist/index.html '}),
      );

      final entry = (await PreviewRemoteDataSourceImp(apiConsumer).getPreview('s-1')).data!;

      expect(entry.entry, 'dist/index.html');
      verify(() => apiConsumer.get(EndPoints.sessionPreview('s-1'))).called(1);
    });

    test('treats a missing entry as an empty one', () async {
      final apiConsumer = _MockApiConsumer();
      when(() => apiConsumer.get(any())).thenAnswer((_) async => _response(const {}));

      expect((await PreviewRemoteDataSourceImp(apiConsumer).getPreview('s-1')).data!.entry, isEmpty);
    });
  });

  group('repository', () {
    late _MockDataSource dataSource;
    late _MockNetworkStatus network;
    late _MockConfigStore configStore;
    late PreviewRepository repository;

    setUp(() {
      dataSource = _MockDataSource();
      network = _MockNetworkStatus();
      configStore = _MockConfigStore();
      repository = PreviewRepositoryImp(dataSource, network, configStore);
      when(() => network.isConnected).thenAnswer((_) async => true);
      when(() => configStore.current).thenReturn(
        const ServerConfig(host: '10.0.0.5', httpPort: '3011', secure: false, password: 'secret12'),
      );
    });

    test('builds the URL from our own base, not the daemon report', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: 'dist/index.html')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, 'http://10.0.0.5:3011/api/v1/sessions/s-1/preview/files/dist/index.html');
      expect(preview!.authenticated, isTrue);
    });

    test('honours the TLS toggle when building the base', () async {
      when(() => configStore.current).thenReturn(
        const ServerConfig(host: 'box.ts.net', httpPort: '443', secure: true, password: 'p'),
      );
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: 'index.html')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, startsWith('https://box.ts.net:443/'));
    });

    test('falls back to a phone-reachable dev server without forwarding auth', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: '')),
      );

      final result = await repository.getPreview('s-1', previewUrl: 'http://localhost:5173/');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview!.url, 'http://10.0.0.5:5173/');
      expect(preview!.authenticated, isFalse);
      expect(preview!.entry, '10.0.0.5');
    });

    test('reports no preview at all when there is neither an entry nor a dev server', () async {
      when(() => dataSource.getPreview(any())).thenAnswer(
        (_) async => const GlobalResponse(data: PreviewEntryModel(entry: '')),
      );

      final result = await repository.getPreview('s-1');

      late PreviewModel? preview;
      result.when(onSuccess: (value) => preview = value, onFailure: (_) {});
      expect(preview, isNull);
    });

    test('short-circuits to a failure when offline', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      expect((await repository.getPreview('s-1')).isFailure, isTrue);
      verifyNever(() => dataSource.getPreview(any()));
    });
  });
}
