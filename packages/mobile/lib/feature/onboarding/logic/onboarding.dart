enum LaunchDestination { onboarding, desktops, sessions }

LaunchDestination launchDestination({required int desktopCount, required bool hasActive}) {
  if (desktopCount == 0) return LaunchDestination.onboarding;
  return hasActive ? LaunchDestination.sessions : LaunchDestination.desktops;
}
