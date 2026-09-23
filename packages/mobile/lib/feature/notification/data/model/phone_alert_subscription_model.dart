import 'package:equatable/equatable.dart';

class PhoneAlertSubscriptionModel extends Equatable {
  const PhoneAlertSubscriptionModel({this.topic, this.server});

  final String? topic;
  final String? server;

  factory PhoneAlertSubscriptionModel.fromJson(Map<String, dynamic> json) =>
      PhoneAlertSubscriptionModel(topic: json['topic'] as String?, server: json['server'] as String?);

  @override
  List<Object?> get props => [topic, server];
}
