import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/saved_connection.dart';

part 'connections_state.dart';

/// UI-only for now — dummy data (`docs/design/connections/connections.md`).
/// There is no multi-connection persistence layer yet (`ServerConfigStore`
/// only holds one active `ServerConfig`), so this cubit keeps its list
/// in-memory rather than reading/writing a repository.
class ConnectionsCubit extends Cubit<ConnectionsState> {
  ConnectionsCubit()
    : connections = const [
        SavedConnection(
          id: 'alex-macbook-pro',
          name: "Alex's MacBook Pro",
          address: '100.94.12.3',
          lastConnectedLabel: '2h ago',
        ),
        SavedConnection(
          id: 'office-imac',
          name: 'Office iMac',
          address: '192.168.1.42',
          lastConnectedLabel: '3d ago',
        ),
      ],
      super(const ConnectionsInitialState());

  List<SavedConnection> connections;
  String? connectingId;
  Timer? _connectTimer;

  SavedConnection? byId(String id) {
    for (final connection in connections) {
      if (connection.id == id) return connection;
    }
    return null;
  }

  // TODO(connections): drive this from real pairing/connect state once the
  // daemon supports multiple saved connections, instead of this fixed delay
  // (the prototype itself is a stub — see connections.md's States section).
  void connectTo(String id) {
    connectingId = id;
    emit(ConnectLoadingState(id));
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(milliseconds: 900), () {
      connectingId = null;
      emit(ConnectSuccessState(id));
    });
  }

  void addConnection({required String name, required String address}) {
    connections = [...connections, SavedConnection(id: _generateId(), name: name, address: address)];
    emit(const AddConnectionSuccessState());
  }

  void updateConnection(String id, {required String name, required String address}) {
    connections = [
      for (final connection in connections)
        if (connection.id == id) connection.copyWith(name: name, address: address) else connection,
    ];
    emit(const UpdateConnectionSuccessState());
  }

  void removeConnection(String id) {
    connections = connections.where((connection) => connection.id != id).toList();
    emit(const RemoveConnectionSuccessState());
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Future<void> close() {
    _connectTimer?.cancel();
    return super.close();
  }
}
