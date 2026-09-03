/// Where a CDC event stream starts.
///
/// The daemon's `change_log` sequence and a conversation's `latestSequence` are
/// unrelated counters that are both plain integers. Passing the second where the
/// first belongs silences the stream permanently, because the endpoint drops
/// every event at or below the cursor it is given. This type exists so that
/// mistake cannot compile.
sealed class CdcCursor {
  const CdcCursor();

  const factory CdcCursor.at(int seq) = CdcCursorAt;

  const factory CdcCursor.latest() = CdcCursorLatest;

  Map<String, dynamic> get queryParameters;
}

final class CdcCursorAt extends CdcCursor {
  const CdcCursorAt(this.seq);

  final int seq;

  @override
  Map<String, dynamic> get queryParameters => {'after': seq < 0 ? 0 : seq};
}

final class CdcCursorLatest extends CdcCursor {
  const CdcCursorLatest();

  @override
  Map<String, dynamic> get queryParameters => const {'fromLatest': true};
}
