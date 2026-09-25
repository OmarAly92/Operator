import 'dart:async';

import 'package:equatable/equatable.dart';

enum ConnectionOutcome { online, unreachable, auth, rateLimited, serverError }

class ConnectionReport extends Equatable {
  const ConnectionReport(this.outcome, {required this.path, required this.at});

  final ConnectionOutcome outcome;
  final String path;
  final DateTime at;

  @override
  List<Object?> get props => [outcome, path, at];
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
