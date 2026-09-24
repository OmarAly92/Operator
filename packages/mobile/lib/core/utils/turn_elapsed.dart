String turnElapsed(Duration elapsed, {bool spaced = false}) {
  final seconds = elapsed.inSeconds.clamp(0, 1 << 31);
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m${spaced ? ' ' : ''}${seconds % 60}s';
  return '${seconds ~/ 3600}h ${seconds % 3600 ~/ 60}m';
}
