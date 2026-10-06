import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:operator_mobile/core/api/server_config.dart';

enum ConnectionOutcome { online, unreachable, auth, rateLimited, serverError }

class ConnectionReport extends Equatable {
  const ConnectionReport(this.outcome, {required this.path, required this.at, this.sentTo});

  final ConnectionOutcome outcome;
  final String path;
  final DateTime at;
  final ServerConfig? sentTo;

  @override
  List<Object?> get props => [outcome, path, at, sentTo];
}

class ConnectionReports {
  final StreamController<ConnectionReport> _controller = StreamController<ConnectionReport>.broadcast(sync: true);
  ConnectionReport? _last;

  ConnectionReport? get last => _last;

  Stream<ConnectionReport> get stream => _controller.stream;

  void add(ConnectionReport report) {
    _last = report;
    _controller.add(report);
  }
}
