String relativeTime(String? iso, {DateTime? now}) {
  if (iso == null) return '';
  final then = DateTime.tryParse(iso);
  if (then == null) return '';

  final seconds = (now ?? DateTime.now()).difference(then).inSeconds;
  if (seconds < 60) return 'now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d';
  return '${days ~/ 7}w';
}
