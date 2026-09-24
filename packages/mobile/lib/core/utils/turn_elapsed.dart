String turnElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds.clamp(0, 1 << 31);
  return seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m${seconds % 60}s';
}
