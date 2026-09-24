import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../providers/onboarding_provider.dart';

/// تلميح قصير قابل للإغلاق عند أول استخدام لكل إجراء مهم (سياسة العمل، مبدأ
/// 11) — يُخفى نفسه دائمًا بعد أول ظهور، بمعرّف فريد لكل موضع.
class OnboardingTip extends ConsumerWidget {
  const OnboardingTip({super.key, required this.id, required this.text});

  final String id;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingProvider.select((s) => s.contains(id)));
    if (seen) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SaloniBanner(
        tone: SaloniBannerTone.info,
        body: text,
        action: TextButton(
          onPressed: () => ref.read(onboardingProvider.notifier).markSeen(id),
          child: const Text('فهمت'),
        ),
      ),
    );
  }
}
