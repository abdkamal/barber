import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هل شاهد المستخدم جولة/تلميح كل شاشة رئيسية من قبل — تلميحات قابلة للإغلاق
/// عند أول استخدام (مبدأ السياسة رقم 11).
class OnboardingController extends StateNotifier<Set<String>> {
  OnboardingController() : super({}) {
    _load();
  }

  static const _key = 'saloni_onboarding_seen';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_key) ?? []).toSet();
    } catch (_) {}
  }

  bool hasSeen(String tipId) => state.contains(tipId);

  Future<void> markSeen(String tipId) async {
    if (state.contains(tipId)) return;
    state = {...state, tipId};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.toList());
    } catch (_) {}
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingController, Set<String>>((ref) => OnboardingController());
