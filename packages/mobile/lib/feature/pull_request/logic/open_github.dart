import 'package:operator_mobile/feature/pull_request/logic/github_link.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openGitHub(String url) async {
  final appUrl = githubAppUrl(url);
  if (appUrl != null) {
    try {
      final appUri = Uri.parse(appUrl);
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri);
        return;
      }
    } catch (_) {
      // Falls through to the browser.
    }
  }
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Every failure path already reduces to "nothing opened", as in RN.
  }
}
