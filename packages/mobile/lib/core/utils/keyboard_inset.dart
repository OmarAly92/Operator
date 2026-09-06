const double kMinDockInset = 8;

double dockInset(double keyboardHeight, double safeAreaBottom) {
  if (keyboardHeight > 0) return 0;
  return safeAreaBottom > 0 ? safeAreaBottom : kMinDockInset;
}
