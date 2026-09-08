import 'package:equatable/equatable.dart';

class SavedConnection extends Equatable {
  const SavedConnection({
    required this.id,
    required this.name,
    required this.address,
    this.lastConnectedLabel,
  });

  final String id;
  final String name;
  final String address;
  final String? lastConnectedLabel;

  SavedConnection copyWith({String? name, String? address}) => SavedConnection(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    lastConnectedLabel: lastConnectedLabel,
  );

  @override
  List<Object?> get props => [id, name, address, lastConnectedLabel];
}
