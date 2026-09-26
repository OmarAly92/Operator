import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/connection/connection_report.dart';
import 'package:operator_mobile/core/database/app_database.dart';
import 'package:operator_mobile/core/database/tables/desktop/desktop_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_block_event/replica_block_event_dao.dart';
import 'package:operator_mobile/core/database/tables/replica_document/replica_document_dao.dart';
import 'package:operator_mobile/core/database/tables/settings/settings_dao.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/core/notifications/local_alert_sink.dart';
import 'package:operator_mobile/core/notifications/phone_alerts_runtime.dart';
import 'package:operator_mobile/feature/dictation/device_provider.dart';
import 'package:operator_mobile/feature/dictation/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/dictation/speech_recognizer.dart';
import 'package:operator_mobile/feature/dictation/voice_types.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/background_tasks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_local_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/session_control_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/repository/background_tasks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/data/repository/session_control_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_command_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_local_data_source.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/desktops_local_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_local_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/data_source/spawn_remote_data_source.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/attachment_picker.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/slash_menu_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/usage/data/data_source/usage_remote_data_source.dart';
import 'package:operator_mobile/feature/usage/data/repository/usage_repository.dart';
import 'package:operator_mobile/feature/usage/presentation/usage_screen/logic/usage_cubit.dart';

final sl = GetIt.instance;

class ServiceLocator {
  static Future<void> init() async {
    await _coreSetup();
    _pairingFeatureSetup();
    _sessionsFeatureSetup();
    _pullRequestFeatureSetup();
    _spawnFeatureSetup();
    _settingsFeatureSetup();
    _terminalFeatureSetup();
    _usageFeatureSetup();
    _blocksFeatureSetup();
    _notificationFeatureSetup();
    _voiceSetup();
    _previewFeatureSetup();
  }

  static Future<void> _coreSetup() async {
    sl.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage(),
    );

    sl.registerLazySingleton<AppDatabase>(
      () => AppDatabase(onWipe: () => DesktopsLocalDataSourceImp.purgePasswords(sl<FlutterSecureStorage>())),
    );
    sl.registerLazySingleton<DesktopDao>(() => DesktopDao(sl<AppDatabase>()));
    sl.registerLazySingleton<SettingsDao>(() => SettingsDao(sl<AppDatabase>()));
    sl.registerLazySingleton<ReplicaDocumentDao>(() => ReplicaDocumentDao(sl<AppDatabase>()));
    sl.registerLazySingleton<ReplicaBlockEventDao>(() => ReplicaBlockEventDao(sl<AppDatabase>()));
    sl.registerLazySingleton<DesktopsLocalDataSource>(
      () => DesktopsLocalDataSourceImp(sl<DesktopDao>(), sl<FlutterSecureStorage>()),
    );
    sl.registerLazySingleton<DesktopsRepository>(() => DesktopsRepositoryImp(sl<DesktopsLocalDataSource>()));

    sl.registerLazySingleton<ServerConfigStore>(
      () => ServerConfigStore(sl<DesktopsLocalDataSource>()),
    );
    sl.registerLazySingleton<ConnectionReports>(ConnectionReports.new);
    sl.registerLazySingleton<ApiConsumer>(
      () => DioConsumer(sl<ServerConfigStore>(), reports: sl<ConnectionReports>()),
    );
    sl.registerLazySingleton<NetworkStatus>(
      () => NetworkStatusImp(sl<ApiConsumer>(), sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<MuxClient>(
      () => MuxClient(sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<ConnectionCubit>(() {
      final connection = ConnectionCubit(
        sl<ConnectionReports>(),
        sl<MuxClient>().status,
        sl<ServerConfigStore>(),
        desktopNames: sl<ServerConfigStore>().activeDesktopName,
      );
      sl<MuxClient>().bindConnection(connection);
      return connection;
    });
    sl.registerLazySingleton<GlobalKey<NavigatorState>>(
      () => GlobalKey<NavigatorState>(),
    );
    sl.registerLazySingleton<DeepLinkService>(
      () => DeepLinkService(AppLinksSource(), sl<GlobalKey<NavigatorState>>(), sl<ServerConfigStore>()),
    );
  }

  static void _pairingFeatureSetup() {
    sl.registerFactoryParam<PairingScanCubit, bool, void>(
      (fromOnboarding, _) => PairingScanCubit(
        sl<PairingRepository>(),
        sl<ServerConfigStore>(),
        fromOnboarding: fromOnboarding,
      ),
    );
    sl.registerFactoryParam<ManualConnectCubit, ManualConnectMode, void>(
      (mode, _) => ManualConnectCubit(sl<PairingRepository>(), sl<ServerConfigStore>(), mode: mode),
    );
    sl.registerFactory<ConnectionsCubit>(
      () => ConnectionsCubit(sl<DesktopsRepository>(), sl<PairingRemoteDataSource>(), sl<ServerConfigStore>()),
    );

    sl.registerLazySingleton<PairingRepository>(
      () => PairingRepositoryImp(
        sl<PairingRemoteDataSource>(),
        sl<DesktopsRepository>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<PairingRemoteDataSource>(
      () => PairingRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _sessionsFeatureSetup() {
    sl.registerLazySingleton<SessionsCubit>(
      () => SessionsCubit(
        sl<SessionsRepository>(),
        sl<MuxClient>(),
        sl<ServerConfigStore>(),
        connection: sl<ConnectionCubit>(),
      ),
    );

    sl.registerLazySingleton<SessionsRepository>(
      () => SessionsRepositoryImp(
        sl<SessionsRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<SessionsLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<SessionsLocalDataSource>(
      () => SessionsLocalDataSourceImp(sl<ReplicaDocumentDao>()),
    );
    sl.registerLazySingleton<SessionsRemoteDataSource>(
      () => SessionsRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _pullRequestFeatureSetup() {
    sl.registerFactory<PullRequestCubit>(
      () => PullRequestCubit(sl<PullRequestRepository>()),
    );

    sl.registerLazySingleton<PullRequestRepository>(
      () => PullRequestRepositoryImp(
        sl<PullRequestRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<PullRequestRemoteDataSource>(
      () => PullRequestRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _spawnFeatureSetup() {
    sl.registerFactory<SpawnCubit>(() => SpawnCubit(sl<SpawnRepository>()));

    sl.registerLazySingleton<SpawnRepository>(
      () =>
          SpawnRepositoryImp(sl<SpawnRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<SpawnRemoteDataSource>(
      () => SpawnRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _settingsFeatureSetup() {
    sl.registerFactory<SettingsCubit>(
      () => SettingsCubit(sl<SessionsRepository>(), sl<ServerConfigStore>(), sl<DesktopsRepository>()),
    );
  }

  static void _terminalFeatureSetup() {
    sl.registerFactoryParam<TerminalCubit, TerminalArgs, void>(
      (args, _) => TerminalCubit(
        sl<MuxClient>(),
        sl<TerminalRepository>(),
        sl<SessionsRepository>(),
        args,
      ),
    );
    sl.registerLazySingleton<TerminalRepository>(
      () => TerminalRepositoryImp(
        sl<TerminalRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<TerminalRemoteDataSource>(
      () => TerminalRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerLazySingleton<AttachmentPicker>(() => AttachmentPickerImp(ImagePicker()));
    sl.registerFactoryParam<SlashMenuCubit, TextEditingController, String>(
      (composer, sessionId) => SlashMenuCubit(sl<TerminalRepository>(), composer, sessionId: sessionId),
    );
  }

  static void _blocksFeatureSetup() {
    sl.registerFactoryParam<SessionCommandCubit, String, String?>(
      (sessionId, activity) => SessionCommandCubit(
        sl<MuxClient>(),
        sl<SessionControlRepository>(),
        sl<UsageRepository>(),
        sessionId: sessionId,
        initialActivity: activity,
      ),
    );
    sl.registerFactoryParam<BlocksCubit, BlocksScope, void>(
      (scope, _) => BlocksCubit(
        sl<MuxClient>(),
        sl<BlocksRepository>(),
        scope,
        tasks: sl<BackgroundTasksRepository>(),
        connection: sl<ConnectionCubit>(),
      ),
    );
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(
        persistedViewMode(sessionViewKey(args)) ?? defaultViewMode(args),
        persistKey: sessionViewKey(args),
      ),
    );
    sl.registerLazySingleton<BlocksRepository>(
      () => BlocksRepositoryImp(
        sl<BlocksRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<BlocksLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<BlocksLocalDataSource>(
      () => BlocksLocalDataSourceImp(sl<ReplicaBlockEventDao>()),
    );
    sl.registerLazySingleton<BlocksRemoteDataSource>(
      () => BlocksRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerLazySingleton<BackgroundTasksRepository>(
      () => BackgroundTasksRepositoryImp(
        sl<BackgroundTasksRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<BackgroundTasksRemoteDataSource>(
      () => BackgroundTasksRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerLazySingleton<SessionControlRepository>(
      () => SessionControlRepositoryImp(
        sl<SessionControlRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<SessionControlRemoteDataSource>(
      () => SessionControlRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _usageFeatureSetup() {
    sl.registerLazySingleton<UsageRepository>(
      () => UsageRepository(sl<UsageRemoteDataSource>()),
    );
    sl.registerLazySingleton<UsageRemoteDataSource>(
      () => UsageRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerFactory<UsageCubit>(() => UsageCubit(sl<UsageRepository>()));
  }

  static void _notificationFeatureSetup() {
    sl.registerLazySingleton<LocalAlertSink>(FlutterLocalAlertSink.new);
    sl.registerLazySingleton<PhoneAlertsRuntime>(
      () => PhoneAlertsRuntime(sl<MuxClient>(), sl<LocalAlertSink>(), (uri) => sl<DeepLinkService>().handle(uri)),
    );
    sl.registerLazySingleton<NotificationsCubit>(
      () => NotificationsCubit(
        sl<NotificationRepository>(),
        sl<ServerConfigStore>(),
        connection: sl<ConnectionCubit>(),
      ),
    );

    sl.registerLazySingleton<NotificationRepository>(
      () => NotificationRepositoryImp(
        sl<NotificationRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<NotificationLocalDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<NotificationLocalDataSource>(
      () => NotificationLocalDataSourceImp(sl<ReplicaDocumentDao>()),
    );
    sl.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerFactory<PhoneAlertsCubit>(
      () => PhoneAlertsCubit(
        sl<NotificationRepository>(),
        launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
        copy: (text) => Clipboard.setData(ClipboardData(text: text)),
        ntfyDeepLink: false,
      ),
    );
  }

  static void _voiceSetup() {
    sl.registerLazySingleton<VoiceProvider>(
      () => DeviceVoiceProvider(SpeechToTextRecognizer()),
    );
    sl.registerFactoryParam<VoiceInputCubit, void Function(String), void>(
      (onTranscript, _) =>
          VoiceInputCubit(sl<VoiceProvider>(), onTranscript: onTranscript),
    );
  }

  static void _previewFeatureSetup() {
    sl.registerFactoryParam<PreviewCubit, String, String?>(
      (sessionId, previewUrl) => PreviewCubit(
        sl<PreviewRepository>(),
        sessionId,
        previewUrl: previewUrl,
      ),
    );

    sl.registerLazySingleton<PreviewRepository>(
      () => PreviewRepositoryImp(
        sl<PreviewRemoteDataSource>(),
        sl<NetworkStatus>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<PreviewRemoteDataSource>(
      () => PreviewRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }
}
