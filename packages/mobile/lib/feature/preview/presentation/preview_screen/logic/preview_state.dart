part of 'preview_cubit.dart';

sealed class PreviewState extends Equatable {
  const PreviewState();

  @override
  List<Object?> get props => [];
}

final class PreviewInitialState extends PreviewState {
  const PreviewInitialState();
}

final class PreviewReadyState extends PreviewState {
  const PreviewReadyState(this.revision);

  final int revision;

  @override
  List<Object?> get props => [revision];
}
