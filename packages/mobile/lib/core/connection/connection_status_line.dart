import 'package:operator_mobile/core/connection/connection_cubit.dart';

enum StatusTone { neutral, attention, danger }

class StatusLine {
  const StatusLine(this.text, {this.tone = StatusTone.neutral, this.busy = false});

  final String text;
  final StatusTone tone;
  final bool busy;
}

StatusLine connectionStatusLine(AppConnectionState state, {required DateTime now, DateTime? fetchedAt}) =>
    switch (state) {
      ConnectionConnectingState() => const StatusLine('Connecting…', busy: true),
      ConnectionOnlineState(:final updatedAt) => StatusLine(_updated(now.difference(updatedAt))),
      ConnectionOfflineState(:final lastSeenAt) => StatusLine(
        _offline(lastSeenAt ?? fetchedAt, now),
        tone: StatusTone.attention,
      ),
      ConnectionAuthFailedState() => const StatusLine('Needs re-pairing', tone: StatusTone.danger),
    };

String _updated(Duration age) => age < const Duration(minutes: 1) ? 'Updated just now' : 'Updated ${_ago(age)} ago';

String _offline(DateTime? seen, DateTime now) {
  if (seen == null) return 'Offline';
  final age = now.difference(seen);
  return age < const Duration(minutes: 1) ? 'Offline · last seen just now' : 'Offline · last seen ${_ago(age)} ago';
}

String _ago(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  return '${age.inDays}d';
}
