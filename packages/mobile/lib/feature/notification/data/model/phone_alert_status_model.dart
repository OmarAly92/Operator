import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/notification/data/model/phone_alert_delivery_model.dart';

class PhoneAlertStatusModel extends Equatable {
  const PhoneAlertStatusModel({this.enabled, this.claimed, this.lastDelivery});

  final bool? enabled;
  final bool? claimed;
  final PhoneAlertDeliveryModel? lastDelivery;

  factory PhoneAlertStatusModel.fromJson(Map<String, dynamic> json) => PhoneAlertStatusModel(
    enabled: json['enabled'] as bool?,
    claimed: json['claimed'] as bool?,
    lastDelivery: json['lastDelivery'] is Map<String, dynamic>
        ? PhoneAlertDeliveryModel.fromJson(json['lastDelivery'] as Map<String, dynamic>)
        : null,
  );

  @override
  List<Object?> get props => [enabled, claimed, lastDelivery];
}
