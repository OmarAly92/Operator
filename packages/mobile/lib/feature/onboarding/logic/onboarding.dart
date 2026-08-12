bool shouldOnboard({required bool? configured, required bool? skipped}) {
  if (configured == null || skipped == null) return false;
  return !configured && !skipped;
}
