import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/feature/chat/voice/logic/voice_input_cubit.dart';
import 'package:operator_mobile/feature/chat/voice/voice_types.dart';

const double kMicSize = 40;

String appendTranscript(String existing, String spoken) =>
    existing.trim().isEmpty ? spoken : '${existing.trimRight()} $spoken';

class MicKey extends StatefulWidget {
  const MicKey({super.key});

  @override
  State<MicKey> createState() => _MicKeyState();
}

class _MicKeyState extends State<MicKey> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse(bool live) {
    if (live == _pulse.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || live == _pulse.isAnimating) return;
      if (live) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse
          ..stop()
          ..value = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<VoiceInputCubit, VoiceInputState>(
      buildWhen: (previous, current) => current is VoiceInputReadyState,
      builder: (context, state) {
        final cubit = context.read<VoiceInputCubit>();
        final live =
            cubit.phase == VoiceState.recording ||
            cubit.phase == VoiceState.starting;
        final latched = live && cubit.mode == VoiceMode.latched;
        final denied = cubit.phase == VoiceState.denied;
        final unavailable = cubit.phase == VoiceState.unavailable;
        final disabled = denied || unavailable;
        _syncPulse(live);

        final fill = live
            ? skin.red
            : denied
            ? skin.tintRed
            : unavailable
            ? skin.bgElevated
            : skin.tintBlue;
        final ink = live
            ? skin.textPrimary
            : denied
            ? skin.red
            : unavailable
            ? skin.textFaint
            : skin.blue;

        return SizedBox(
          width: kMicSize,
          height: kMicSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (live)
                FadeTransition(
                  opacity: Tween<double>(begin: 0.45, end: 0).animate(_pulse),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1, end: 1.45).animate(_pulse),
                    child: Container(
                      width: kMicSize,
                      height: kMicSize,
                      decoration: BoxDecoration(
                        color: skin.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                enabled: !disabled,
                label: unavailable
                    ? 'Dictation unavailable on this device'
                    : latched
                    ? 'Stop dictating'
                    : 'Hold to dictate, or double-tap for hands-free',
                child: GestureDetector(
                  onTapDown: disabled
                      ? null
                      : (_) {
                          Haptics.tap();
                          cubit.pressIn();
                        },
                  onTapUp: disabled ? null : (_) => cubit.pressOut(),
                  onTapCancel: disabled ? null : cubit.pressCancel,
                  child: Container(
                    width: kMicSize,
                    height: kMicSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(12),
                      border: latched
                          ? Border.all(color: skin.textPrimary, width: 2)
                          : unavailable
                          ? Border.all(color: skin.borderSubtle)
                          : null,
                    ),
                    child: Icon(
                      disabled ? Icons.mic_off : Icons.mic,
                      size: 18,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
