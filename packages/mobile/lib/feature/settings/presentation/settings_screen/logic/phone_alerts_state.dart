part of 'phone_alerts_cubit.dart';

class PhoneAlertsState extends Equatable {
  const PhoneAlertsState({this.status, this.lastTest, this.busy = false, this.copiedTopic = false, this.error = ''});

  final PhoneAlertStatusModel? status;
  final PhoneAlertDeliveryModel? lastTest;
  final bool busy;
  final bool copiedTopic;
  final String error;

  PhoneAlertsState copyWith({
    PhoneAlertStatusModel? status,
    PhoneAlertDeliveryModel? lastTest,
    bool? busy,
    bool? copiedTopic,
    String? error,
  }) => PhoneAlertsState(
    status: status ?? this.status,
    lastTest: lastTest ?? this.lastTest,
    busy: busy ?? this.busy,
    copiedTopic: copiedTopic ?? this.copiedTopic,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [status, lastTest, busy, copiedTopic, error];
}
