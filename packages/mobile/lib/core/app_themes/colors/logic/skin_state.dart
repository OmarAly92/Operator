part of 'skin_cubit.dart';

sealed class SkinState extends Equatable {
  const SkinState();

  @override
  List<Object?> get props => [];
}

final class SkinInitialState extends SkinState {
  const SkinInitialState();
}

final class SkinChangedState extends SkinState {
  const SkinChangedState(this.skin);

  final AppSkin skin;

  @override
  List<Object?> get props => [skin];
}
