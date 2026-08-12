import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/camera_permission_gate.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

class PairingScanBody extends StatefulWidget {
  const PairingScanBody({super.key});

  @override
  State<PairingScanBody> createState() => _PairingScanBodyState();
}

class _PairingScanBodyState extends State<PairingScanBody> {
  final _controller = MobileScannerController(lensType: CameraLensType.normal);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    context.read<PairingScanCubit>().onScan(raw, Theme.of(context).platform);
  }

  Future<void> _onManualConnect() async {
    final paired = await Navigator.of(context).pushNamed<bool>(RoutesStrings.manualConnect);
    if (paired != true || !mounted) return;
    final fromOnboarding = context.read<PairingScanCubit>().fromOnboarding;
    if (fromOnboarding) {
      Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, exception) => const CameraPermissionGate(),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: TextButton(
              onPressed: _onManualConnect,
              child: AppText('Enter manually', style: AppTextStyle.style14Medium.copyWith(color: skin.accent)),
            ),
          ),
        ),
        BlocBuilder<PairingScanCubit, PairingScanState>(
          buildWhen: (previous, current) => current is VerifyLoadingState || current is VerifyFailureState || current is PairingScanInitialState,
          builder: (context, state) {
            if (state is VerifyLoadingState) {
              return ColoredBox(color: skin.scrim, child: const AppLoader.center());
            }
            if (state is VerifyFailureState) {
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConnectionFailureBanner(copy: state.copy),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
