import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/feature/pairing/data/data_source/pairing_remote_data_source.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/data/model/params/rename_desktop_params.dart';
import 'package:operator_mobile/feature/pairing/data/repository/desktops_repository.dart';

part 'connections_state.dart';

class ConnectionsCubit extends Cubit<ConnectionsState> {
  ConnectionsCubit(this._desktops, this._remote, this._store) : super(const ConnectionsInitialState()) {
    _subscription = _desktops.watchDesktops().listen(_onDesktops);
  }

  final DesktopsRepository _desktops;
  final PairingRemoteDataSource _remote;
  final ServerConfigStore _store;

  List<DesktopModel> desktops = const [];
  String? connectingId;
  final Map<String, ConnectionErrorCopy> errors = {};
  StreamSubscription<List<DesktopModel>>? _subscription;

  void _onDesktops(List<DesktopModel> next) {
    final hadDesktops = desktops.isNotEmpty;
    desktops = next;
    for (final desktop in next) {
      if (desktop.isActive == true) errors.remove(desktop.id);
    }
    emit(DesktopsUpdatedState(next));
    if (hadDesktops && next.isEmpty) emit(const LastDesktopRemovedState());
  }

  DesktopModel? byId(String id) {
    for (final desktop in desktops) {
      if (desktop.id == id) return desktop;
    }
    return null;
  }

  Future<void> connectTo(String id, TargetPlatform platform) async {
    final desktop = byId(id);
    if (desktop == null || connectingId != null) return;
    connectingId = id;
    errors.remove(id);
    emit(ConnectLoadingState(id));

    try {
      final password = await _desktops.passwordFor(id);
      final config = desktop.toServerConfig(password.valueOrNull ?? '');
      try {
        final identity = await _remote.identify(config);
        if (byId(id) == null) return;
        final activated = await _desktops.activate(id, name: identity.name);
        if (activated.isFailure) {
          _fail(id, desktop, ConnectionFailure.local, platform);
          return;
        }
        _store.set(config);
        emit(ConnectSuccessState(id));
      } on Failure catch (failure) {
        _fail(id, desktop, classifyConnectionFailure(failure.statusCode), platform);
      }
    } finally {
      connectingId = null;
    }
  }

  void _fail(String id, DesktopModel desktop, ConnectionFailure reason, TargetPlatform platform) {
    final copy = describeConnectionFailure(
      reason,
      host: desktop.host ?? '',
      port: desktop.port ?? '',
      platform: platform,
    );
    errors[id] = copy;
    emit(ConnectFailureState(id, copy));
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _desktops.rename(RenameDesktopParams(id: id, name: trimmed));
  }

  Future<void> remove(String id) async {
    final wasActive = byId(id)?.isActive ?? false;
    final result = await _desktops.remove(id);
    if (result.isFailure) return;
    errors.remove(id);
    if (wasActive) _store.clear();
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
