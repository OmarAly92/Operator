import 'package:equatable/equatable.dart';

class PhoneAlertDeliveryModel extends Equatable {
  const PhoneAlertDeliveryModel({this.at, this.ok, this.error});

  final DateTime? at;
  final bool? ok;
  final String? error;

  factory PhoneAlertDeliveryModel.fromJson(Map<String, dynamic> json) => PhoneAlertDeliveryModel(
    at: DateTime.tryParse(json['at'] as String? ?? ''),
    ok: json['ok'] as bool?,
    error: json['error'] as String?,
  );

  @override
  List<Object?> get props => [at, ok, error];
}
