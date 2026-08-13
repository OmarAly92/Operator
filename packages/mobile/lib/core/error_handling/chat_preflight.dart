import 'package:operator_mobile/core/error_handling/failures/failure.dart';

const Set<String> _chatPreflightCodes = {
  'SESSION_MODE_UNSUPPORTED',
  'CHAT_DRIVER_UNAVAILABLE',
  'CHAT_DRIVER_INCOMPATIBLE',
  'CHAT_AUTH_REQUIRED',
};

final RegExp _httpEnvelope = RegExp(r'^\d+\s+[^-]+\s+-\s+');

bool isChatPreflightFailure(Failure failure) =>
    failure.apiStatus != null && _chatPreflightCodes.contains(failure.apiStatus);

String chatErrorCopy(Failure failure) {
  final stripped = failure.message.replaceFirst(_httpEnvelope, '').trim();
  return stripped.isEmpty ? 'Chat is unavailable for this agent.' : stripped;
}
