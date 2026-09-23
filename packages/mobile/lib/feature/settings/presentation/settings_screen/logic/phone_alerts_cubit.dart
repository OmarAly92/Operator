import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_status_model.dart';
import 'package:operator_mobile/feature/notification/data/repository/notification_repository.dart';

part 'phone_alerts_state.dart';

const String kNtfyAppStoreUrl = 'https://apps.apple.com/us/app/ntfy/id1625396347';

class PhoneAlertsCubit extends Cubit<PhoneAlertsState> {
  PhoneAlertsCubit(this._repository, {required this.launch, required this.copy, this.ntfyDeepLink = true})
    : super(const PhoneAlertsState());

  final NotificationRepository _repository;
  final Future<bool> Function(Uri uri) launch;
  final Future<void> Function(String text) copy;
  final bool ntfyDeepLink;

  Future<void> load() => _refresh(clearError: true);

  Future<void> _refresh({required bool clearError}) async {
    final result = await _repository.getPhoneAlerts();
    result.when(
      onSuccess: (status) => emit(state.copyWith(status: status, error: clearError ? '' : null)),
      onFailure: (failure) => emit(state.copyWith(error: "Couldn't reach the desktop: ${failure.message}")),
    );
  }

  Future<void> subscribe() async {
    emit(state.copyWith(busy: true));
    final result = await _repository.subscribePhoneAlerts();
    String? topic;
    String server = 'https://ntfy.sh';
    result.when(
      onSuccess: (sub) {
        topic = sub.topic;
        server = sub.server ?? server;
        emit(state.copyWith(error: ''));
      },
      onFailure: (failure) => emit(state.copyWith(busy: false, error: failure.message)),
    );
    if (topic == null || topic!.isEmpty) {
      emit(state.copyWith(busy: false));
      return;
    }
    final host = Uri.parse(server).host;
    final deepLinkOpened = ntfyDeepLink && await launch(Uri.parse('ntfy://$host/$topic'));
    var copiedTopic = false;
    if (!deepLinkOpened) {
      copiedTopic = true;
      await copy(topic!);
      final ntfyOpened = await launch(Uri.parse('ntfy://'));
      if (!ntfyOpened) {
        await launch(Uri.parse(kNtfyAppStoreUrl));
      }
    }
    emit(state.copyWith(busy: false, copiedTopic: copiedTopic));
    await _refresh(clearError: false);
  }

  Future<void> sendTest() async {
    emit(state.copyWith(busy: true));
    final result = await _repository.testPhoneAlert();
    result.when(
      onSuccess: (delivery) => emit(state.copyWith(busy: false, lastTest: delivery, error: '')),
      onFailure: (failure) => emit(state.copyWith(busy: false, error: failure.message)),
    );
    await _refresh(clearError: false);
  }
}
