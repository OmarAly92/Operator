
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:operator_mobile/core/api/api_request_helpers/api_consumer.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/deep_link/deep_link_service.dart';
import 'package:operator_mobile/core/events/conversation_event_bus.dart';
import 'package:operator_mobile/core/helpers/network/network_status.dart';
import 'package:operator_mobile/core/mux/mux_client.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_event_data_source.dart';
import 'package:operator_mobile/feature/chat/data/data_source/chat_remote_data_source.dart';
import 'package:operator_mobile/feature/chat/data/repository/chat_repository.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/device_provider.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/speech_recognizer.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';
import 'package:operator_mobile/feature/blocks/data/data_source/blocks_remote_data_source.dart';
import 'package:operator_mobile/feature/blocks/data/repository/blocks_repository.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/conversation_blocks_cubit.dart';
import 'package:operator_mobile/feature/blocks/presentation/blocks_screen/logic/session_view_cubit.dart';
import 'package:operator_mobile/feature/notification/data/data_source/notification_remote_data_source.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_registration.dart';
import 'package:operator_mobile/feature/notification/logic/push_token_source.dart';
import 'package:operator_mobile/feature/notification/presentation/notifications_screen/logic/notifications_cubit.dart';
import 'package:operator_mobile/feature/orchestrator/data/data_source/orchestrator_remote_data_source.dart';
import 'package:operator_mobile/feature/orchestrator/data/repository/orchestrator_repository.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/logic/orchestrator_cubit.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/repository/pairing_repository.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/preview/data/data_source/preview_remote_data_source.dart';
import 'package:operator_mobile/feature/preview/data/repository/preview_repository.dart';
import 'package:operator_mobile/feature/preview/presentation/preview_screen/logic/preview_cubit.dart';
import 'package:operator_mobile/feature/pull_request/data/data_source/pull_request_remote_data_source.dart';
import 'package:operator_mobile/feature/pull_request/data/repository/pull_request_repository.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/sessions/data/data_source/sessions_remote_data_source.dart';
import 'package:operator_mobile/feature/sessions/data/repository/sessions_repository.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/spawn/data/data_source/spawn_remote_data_source.dart';
import 'package:operator_mobile/feature/spawn/data/repository/spawn_repository.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/logic/spawn_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/terminal_remote_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sl = GetIt.instance;

class ServiceLocator {
  static Future<void> init() async {
    await _coreSetup();
    _pairingFeatureSetup();
    _sessionsFeatureSetup();
    _pullRequestFeatureSetup();
    _orchestratorFeatureSetup();
    _spawnFeatureSetup();
    _settingsFeatureSetup();
    _chatFeatureSetup();
    _terminalFeatureSetup();
    _blocksFeatureSetup();
    _notificationFeatureSetup();
    _voiceSetup();
    _previewFeatureSetup();
  }

  static Future<void> _coreSetup() async {
    final preferences = await SharedPreferences.getInstance();
    sl.registerLazySingleton<SharedPreferences>(() => preferences);
    sl.registerLazySingleton<FlutterSecureStorage>(
      () => const FlutterSecureStorage(),
    );

    sl.registerLazySingleton<ServerConfigStore>(
      () => ServerConfigStore(sl<FlutterSecureStorage>()),
    );
    sl.registerLazySingleton<ApiConsumer>(
      () => DioConsumer(sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<NetworkStatus>(
      () => NetworkStatusImp(sl<ApiConsumer>(), sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<MuxClient>(
      () => MuxClient(sl<ServerConfigStore>()),
    );
    sl.registerLazySingleton<ConversationEventBus>(
      () => ConversationEventBus(sl<ChatEventDataSource>()),
    );

    sl.registerLazySingleton<GlobalKey<NavigatorState>>(() => GlobalKey<NavigatorState>());
    sl.registerLazySingleton<DeepLinkService>(
      () => DeepLinkService(AppLinksSource(), sl<GlobalKey<NavigatorState>>()),
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
    sl.registerFactory<ManualConnectCubit>(
      () =>
          ManualConnectCubit(sl<PairingRepository>(), sl<ServerConfigStore>()),
    );

    sl.registerLazySingleton<PairingRepository>(
      () => PairingRepositoryImp(
        sl<PairingRemoteDataSource>(),
        sl<ServerConfigStore>(),
      ),
    );
    sl.registerLazySingleton<PairingRemoteDataSource>(
      () => PairingRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _sessionsFeatureSetup() {
    sl.registerLazySingleton<SessionsCubit>(
      () => SessionsCubit(sl<SessionsRepository>(), sl<MuxClient>()),
    );

    sl.registerLazySingleton<SessionsRepository>(
      () => SessionsRepositoryImp(
        sl<SessionsRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
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

  static void _orchestratorFeatureSetup() {
    sl.registerFactory<OrchestratorCubit>(
      () => OrchestratorCubit(sl<OrchestratorRepository>()),
    );

    sl.registerLazySingleton<OrchestratorRepository>(
      () => OrchestratorRepositoryImp(
        sl<OrchestratorRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<OrchestratorRemoteDataSource>(
      () => OrchestratorRemoteDataSourceImp(sl<ApiConsumer>()),
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
      () => SettingsCubit(sl<SessionsRepository>(), sl<ServerConfigStore>()),
    );
  }

  static void _chatFeatureSetup() {
    sl.registerFactoryParam<ChatCubit, String, void>(
      (sessionId, _) => ChatCubit(
        sl<ChatRepository>(),
        sessionId,
        eventBus: sl<ConversationEventBus>(),
      ),
    );

    sl.registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImp(
        sl<ChatRemoteDataSource>(),
        sl<NetworkStatus>(),
      ),
    );
    sl.registerLazySingleton<ChatRemoteDataSource>(
      () => ChatRemoteDataSourceImp(sl<ApiConsumer>()),
    );
    sl.registerLazySingleton<ChatEventDataSource>(
      () => ChatEventDataSourceImp(sl<ApiConsumer>()),
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
      () => TerminalRepositoryImp(sl<TerminalRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<TerminalRemoteDataSource>(
      () => TerminalRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _blocksFeatureSetup() {
    sl.registerFactoryParam<BlocksCubit, String, String?>(
      (sessionId, harness) =>
          BlocksCubit(sl<MuxClient>(), sl<BlocksRepository>(), sessionId, harness: harness),
    );
    sl.registerFactoryParam<ConversationBlocksCubit, String, void>(
      (sessionId, _) => ConversationBlocksCubit(
        sl<ChatRepository>(),
        sl<ConversationEventBus>(),
        sessionId,
      ),
    );
    sl.registerFactoryParam<SessionViewCubit, TerminalArgs, void>(
      (args, _) => SessionViewCubit(defaultViewMode(args)),
    );
    sl.registerLazySingleton<BlocksRepository>(
      () => BlocksRepositoryImp(sl<BlocksRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<BlocksRemoteDataSource>(
      () => BlocksRemoteDataSourceImp(sl<ApiConsumer>()),
    );
  }

  static void _notificationFeatureSetup() {
    sl.registerLazySingleton<NotificationsCubit>(
      () => NotificationsCubit(sl<NotificationRepository>(), sl<ServerConfigStore>()),
    );

    sl.registerLazySingleton<NotificationRepository>(
      () => NotificationRepositoryImp(sl<NotificationRemoteDataSource>(), sl<NetworkStatus>()),
    );
    sl.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSourceImp(sl<ApiConsumer>()),
    );

    sl.registerLazySingleton<PushTokenSource>(() => const UnconfiguredPushTokenSource());
    sl.registerLazySingleton<PushRegistrationStore>(
      () => PushRegistrationStore(FlutterPushSecureStorage(sl<FlutterSecureStorage>())),
    );
    sl.registerLazySingleton<PushRegistrar>(
      () => PushRegistrar(
        sl<NotificationRepository>(),
        sl<PushRegistrationStore>(),
        sl<PushTokenSource>(),
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
      (sessionId, previewUrl) =>
          PreviewCubit(sl<PreviewRepository>(), sessionId, previewUrl: previewUrl),
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
