part of 'voice_input_cubit.dart';

sealed class VoiceInputState extends Equatable {
  const VoiceInputState();

  @override
  List<Object?> get props => [];
}

final class VoiceInputInitialState extends VoiceInputState {
  const VoiceInputInitialState();
}

final class VoiceInputReadyState extends VoiceInputState {
  const VoiceInputReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
