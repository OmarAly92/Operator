import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/helpers/cache/cache_helper.dart';
import 'package:operator_mobile/core/telemetry/events.dart';
import 'package:operator_mobile/core/telemetry/runtime.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/onboarding/presentation/onboarding_screen/ui/widgets/onboarding_step.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  @override
  void initState() {
    super.initState();
    TelemetryRuntime.capture(MobileEvents.onboardingStarted);
  }

  Future<void> _skip(BuildContext context) async {
    TelemetryRuntime.capture(MobileEvents.onboardingSkipped);
    await CacheHelper.save(CacheKeys.onboardingSkipped, true);
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
  }

  void _pair(BuildContext context) {
    Navigator.of(context).pushNamed(RoutesStrings.pairingScan, arguments: {'fromOnboarding': true});
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return PopScope(
      canPop: false,
      child: AppScaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/images/mascot.png', width: 28, height: 28),
                    const HorizontalSpace(8),
                    AppText('Operator', style: AppTextStyle.style15SemiBold),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _skip(context),
                      child: AppText('Skip', style: AppTextStyle.style13Medium.copyWith(color: skin.textSecondary)),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VerticalSpace(24),
                        AppText('Connect your desktop', style: AppTextStyle.style24Bold, maxLines: 2),
                        const VerticalSpace(10),
                        AppText(
                          'Pair with Operator on your computer to check on your agents, jump into any '
                          'terminal, and drive work from your phone.',
                          style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary),
                          maxLines: 4,
                        ),
                        const VerticalSpace(20),
                        PrimaryButton(text: 'Pair Desktop', onPressed: () => _pair(context)),
                        const VerticalSpace(36),
                        AppText(
                          'HOW IT WORKS',
                          style: AppTextStyle.style11SemiBold.copyWith(color: skin.textTertiary),
                        ),
                        const VerticalSpace(14),
                        const OnboardingStep(
                          n: 1,
                          title: 'Open Operator on your computer',
                          hint: 'Go to Settings → Connect Mobile and turn it on.',
                        ),
                        const OnboardingStep(
                          n: 2,
                          title: 'Scan the code',
                          hint: 'Tap Pair Desktop above and point at the QR code on your screen.',
                        ),
                        const OnboardingStep(
                          n: 3,
                          title: "You're connected",
                          hint: 'Your sessions appear here, and you can drive them from your phone.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
