# Why this package is vendored

Forked from `speech_to_text` 7.4.0 and `speech_to_text_platform_interface` 2.4.0 at M6 of the
Flutter mobile port, to recover three capabilities the published packages do not expose and the
RN app depended on:

- `contextualStrings` — biases the recogniser toward coding vocabulary ("git", not "get"; "npm",
  not "MPM"). iOS maps it to `SFSpeechRecognitionRequest.contextualStrings`, Android to
  `RecognizerIntent.EXTRA_BIASING_STRINGS`.
- The iOS audio-session configuration — push-to-talk wants the cheapest session that can capture
  (`.record`, no options, `.default` mode), latched dictation wants a Bluetooth-capable one
  (`.playAndRecord` with `.allowBluetooth` and `.defaultToSpeaker`, `.measurement` mode). The
  session cannot change mid-recording, so the mode is fixed at start. Measured warm-up difference
  is about 1.1s, dominated by Bluetooth HFP route negotiation.
- `EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS` on Android. The package already
  derives `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` from `pauseFor`, but not this one,
  and both are needed to stop Android ending the session while the user is still thinking.

Changes are confined to `SpeechListenOptions`, the method-channel argument map,
`SpeechToTextPlugin.swift` and `SpeechToTextPlugin.kt`. Everything else is upstream 7.4.0 / 2.4.0
verbatim, including the checked-in `.g.dart` files — **do not run `build_runner` here.** The
repository bans generated code in first-party sources; these files are upstream artifacts and are
kept as shipped.

Upstream: https://github.com/csdcorp/speech_to_text
