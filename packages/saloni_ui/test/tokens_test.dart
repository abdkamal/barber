// يتحقق هذا الاختبار من أن كل قيمة في SaloniColors/SaloniSpacing/SaloniRadius/
// SaloniSizes تطابق تمامًا `design/design-system/tokens.json` (مصدر الحقيقة).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

/// يحوّل قيمة hex ("#rrggbb") إلى [Color].
Color _hex(String s) {
  final v = s.replaceFirst('#', '');
  return Color(int.parse('FF$v', radix: 16));
}

/// يحوّل "rgba(r,g,b,a)" إلى [Color].
Color _rgba(String s) {
  final inner = s.substring(s.indexOf('(') + 1, s.indexOf(')'));
  final parts = inner.split(',').map((e) => e.trim()).toList();
  final r = int.parse(parts[0]);
  final g = int.parse(parts[1]);
  final b = int.parse(parts[2]);
  final a = double.parse(parts[3]);
  return Color.fromRGBO(r, g, b, a);
}

Color _parseColor(String s) => s.startsWith('#') ? _hex(s) : _rgba(s);

void _expectColorClose(Color actual, Color expected, String label) {
  // Compare 8-bit channels; rgba() alpha may have float rounding, so allow a
  // very small tolerance there while requiring RGB to match exactly.
  expect(
    (actual.r * 255).round(),
    (expected.r * 255).round(),
    reason: '$label: قناة R',
  );
  expect(
    (actual.g * 255).round(),
    (expected.g * 255).round(),
    reason: '$label: قناة G',
  );
  expect(
    (actual.b * 255).round(),
    (expected.b * 255).round(),
    reason: '$label: قناة B',
  );
  expect(
    ((actual.a * 255).round() - (expected.a * 255).round()).abs() <= 1,
    isTrue,
    reason: '$label: قناة A (${actual.a} vs ${expected.a})',
  );
}

/// يجد ملف tokens.json سواء شُغّل الاختبار من جذر الحزمة أو من جذر المستودع.
File _findTokensFile() {
  final candidates = [
    'design/design-system/tokens.json',
    '../../design/design-system/tokens.json',
    '../design/design-system/tokens.json',
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f;
  }
  throw StateError(
    'tokens.json not found — تأكد من تشغيل الاختبار من جذر المستودع أو من packages/saloni_ui.',
  );
}

void main() {
  final tokensFile = _findTokensFile();
  final Map<String, dynamic> tokens =
      jsonDecode(tokensFile.readAsStringSync()) as Map<String, dynamic>;

  final colorTokens = <String, dynamic>{
    for (final t in (tokens['color']['tokens'] as List))
      (t as Map<String, dynamic>)['name'] as String: t,
  };

  Color expectedColor(String name, String theme) {
    final value = colorTokens[name]!['value'];
    if (value is String) {
      // alias، مثل chart-1 -> "{primary}"
      final aliased = value.replaceAll('{', '').replaceAll('}', '');
      return expectedColor(aliased, theme);
    }
    final map = value as Map<String, dynamic>;
    return _parseColor(map[theme] as String);
  }

  group('SaloniColors — dark', () {
    const c = SaloniColors.dark;
    test('كل الألوان تطابق tokens.json (dark)', () {
      _expectColorClose(c.surface, expectedColor('surface', 'dark'), 'surface');
      _expectColorClose(
        c.surfaceRaised,
        expectedColor('surface-raised', 'dark'),
        'surface-raised',
      );
      _expectColorClose(
        c.surfaceElevated,
        expectedColor('surface-elevated', 'dark'),
        'surface-elevated',
      );
      _expectColorClose(
        c.surfaceSunken,
        expectedColor('surface-sunken', 'dark'),
        'surface-sunken',
      );
      _expectColorClose(c.line, expectedColor('line', 'dark'), 'line');
      _expectColorClose(
        c.lineStrong,
        expectedColor('line-strong', 'dark'),
        'line-strong',
      );
      _expectColorClose(c.ink, expectedColor('ink', 'dark'), 'ink');
      _expectColorClose(
        c.inkMuted,
        expectedColor('ink-muted', 'dark'),
        'ink-muted',
      );
      _expectColorClose(
        c.inkSubtle,
        expectedColor('ink-subtle', 'dark'),
        'ink-subtle',
      );
      _expectColorClose(c.primary, expectedColor('primary', 'dark'), 'primary');
      _expectColorClose(
        c.primaryStrong,
        expectedColor('primary-strong', 'dark'),
        'primary-strong',
      );
      _expectColorClose(
        c.primarySoft,
        expectedColor('primary-soft', 'dark'),
        'primary-soft',
      );
      _expectColorClose(
        c.onPrimary,
        expectedColor('on-primary', 'dark'),
        'on-primary',
      );
      _expectColorClose(c.steel, expectedColor('steel', 'dark'), 'steel');
      _expectColorClose(
        c.steelSoft,
        expectedColor('steel-soft', 'dark'),
        'steel-soft',
      );
      _expectColorClose(c.success, expectedColor('success', 'dark'), 'success');
      _expectColorClose(
        c.successSoft,
        expectedColor('success-soft', 'dark'),
        'success-soft',
      );
      _expectColorClose(c.warning, expectedColor('warning', 'dark'), 'warning');
      _expectColorClose(
        c.warningSoft,
        expectedColor('warning-soft', 'dark'),
        'warning-soft',
      );
      _expectColorClose(c.danger, expectedColor('danger', 'dark'), 'danger');
      _expectColorClose(
        c.dangerSoft,
        expectedColor('danger-soft', 'dark'),
        'danger-soft',
      );
      _expectColorClose(
        c.onDanger,
        expectedColor('on-danger', 'dark'),
        'on-danger',
      );
      _expectColorClose(c.focus, expectedColor('focus', 'dark'), 'focus');
      _expectColorClose(c.overlay, expectedColor('overlay', 'dark'), 'overlay');
      _expectColorClose(c.chart1, expectedColor('chart-1', 'dark'), 'chart-1');
      _expectColorClose(c.chart2, expectedColor('chart-2', 'dark'), 'chart-2');
      _expectColorClose(c.chart3, expectedColor('chart-3', 'dark'), 'chart-3');
    });
  });

  group('SaloniColors — light', () {
    const c = SaloniColors.light;
    test('كل الألوان تطابق tokens.json (light)', () {
      _expectColorClose(c.surface, expectedColor('surface', 'light'), 'surface');
      _expectColorClose(
        c.surfaceRaised,
        expectedColor('surface-raised', 'light'),
        'surface-raised',
      );
      _expectColorClose(
        c.surfaceElevated,
        expectedColor('surface-elevated', 'light'),
        'surface-elevated',
      );
      _expectColorClose(
        c.surfaceSunken,
        expectedColor('surface-sunken', 'light'),
        'surface-sunken',
      );
      _expectColorClose(c.line, expectedColor('line', 'light'), 'line');
      _expectColorClose(
        c.lineStrong,
        expectedColor('line-strong', 'light'),
        'line-strong',
      );
      _expectColorClose(c.ink, expectedColor('ink', 'light'), 'ink');
      _expectColorClose(
        c.inkMuted,
        expectedColor('ink-muted', 'light'),
        'ink-muted',
      );
      _expectColorClose(
        c.inkSubtle,
        expectedColor('ink-subtle', 'light'),
        'ink-subtle',
      );
      _expectColorClose(c.primary, expectedColor('primary', 'light'), 'primary');
      _expectColorClose(
        c.primaryStrong,
        expectedColor('primary-strong', 'light'),
        'primary-strong',
      );
      _expectColorClose(
        c.primarySoft,
        expectedColor('primary-soft', 'light'),
        'primary-soft',
      );
      _expectColorClose(
        c.onPrimary,
        expectedColor('on-primary', 'light'),
        'on-primary',
      );
      _expectColorClose(c.steel, expectedColor('steel', 'light'), 'steel');
      _expectColorClose(
        c.steelSoft,
        expectedColor('steel-soft', 'light'),
        'steel-soft',
      );
      _expectColorClose(c.success, expectedColor('success', 'light'), 'success');
      _expectColorClose(
        c.successSoft,
        expectedColor('success-soft', 'light'),
        'success-soft',
      );
      _expectColorClose(c.warning, expectedColor('warning', 'light'), 'warning');
      _expectColorClose(
        c.warningSoft,
        expectedColor('warning-soft', 'light'),
        'warning-soft',
      );
      _expectColorClose(c.danger, expectedColor('danger', 'light'), 'danger');
      _expectColorClose(
        c.dangerSoft,
        expectedColor('danger-soft', 'light'),
        'danger-soft',
      );
      _expectColorClose(
        c.onDanger,
        expectedColor('on-danger', 'light'),
        'on-danger',
      );
      _expectColorClose(c.focus, expectedColor('focus', 'light'), 'focus');
      _expectColorClose(
        c.overlay,
        expectedColor('overlay', 'light'),
        'overlay',
      );
      _expectColorClose(c.chart1, expectedColor('chart-1', 'light'), 'chart-1');
      _expectColorClose(c.chart2, expectedColor('chart-2', 'light'), 'chart-2');
      _expectColorClose(c.chart3, expectedColor('chart-3', 'light'), 'chart-3');
    });
  });

  test('SaloniSpacing يطابق tokens.json', () {
    double px(String v) => double.parse(v.replaceAll('px', ''));
    final spacing = <String, dynamic>{
      for (final t in (tokens['spacing']['tokens'] as List))
        (t as Map<String, dynamic>)['name'] as String: t,
    };
    expect(SaloniSpacing.space1, px(spacing['space-1']['value'] as String));
    expect(SaloniSpacing.space2, px(spacing['space-2']['value'] as String));
    expect(SaloniSpacing.space3, px(spacing['space-3']['value'] as String));
    expect(SaloniSpacing.space4, px(spacing['space-4']['value'] as String));
    expect(SaloniSpacing.space5, px(spacing['space-5']['value'] as String));
    expect(SaloniSpacing.space6, px(spacing['space-6']['value'] as String));
    expect(SaloniSpacing.space8, px(spacing['space-8']['value'] as String));
    expect(SaloniSpacing.space12, px(spacing['space-12']['value'] as String));
  });

  test('SaloniRadius يطابق tokens.json', () {
    double px(String v) => double.parse(v.replaceAll('px', ''));
    final radius = <String, dynamic>{
      for (final t in (tokens['radius']['tokens'] as List))
        (t as Map<String, dynamic>)['name'] as String: t,
    };
    expect(SaloniRadius.sm, px(radius['radius-sm']['value'] as String));
    expect(SaloniRadius.md, px(radius['radius-md']['value'] as String));
    expect(SaloniRadius.lg, px(radius['radius-lg']['value'] as String));
    expect(SaloniRadius.xl, px(radius['radius-xl']['value'] as String));
    expect(SaloniRadius.full, px(radius['radius-full']['value'] as String));
  });

  test('SaloniSizes يطابق tokens.json', () {
    double px(String v) => double.parse(v.replaceAll('px', ''));
    final size = <String, dynamic>{
      for (final t in (tokens['size']['tokens'] as List))
        (t as Map<String, dynamic>)['name'] as String: t,
    };
    expect(SaloniSizes.controlSm, px(size['control-sm']['value'] as String));
    expect(SaloniSizes.controlMd, px(size['control-md']['value'] as String));
    expect(SaloniSizes.controlLg, px(size['control-lg']['value'] as String));
    expect(SaloniSizes.navHeight, px(size['nav-height']['value'] as String));
  });

  group('SaloniTextStyles', () {
    final groups = tokens['type']['groups'] as List;
    Map<String, dynamic> styleByName(String name) {
      for (final g in groups) {
        for (final s in (g as Map<String, dynamic>)['styles'] as List) {
          if ((s as Map<String, dynamic>)['name'] == name) return s;
        }
      }
      throw StateError('style not found: $name');
    }

    double px(String v) => double.parse(v.replaceAll('px', ''));

    void checkStyle(String name, TextStyle style) {
      test(name, () {
        final spec = styleByName(name);
        final size = px(spec['fontSize'] as String);
        final lineHeight = px(spec['lineHeight'] as String);
        expect(style.fontSize, size, reason: '$name fontSize');
        expect(
          style.height,
          closeTo(lineHeight / size, 0.001),
          reason: '$name lineHeight/fontSize',
        );
        expect(
          style.fontWeight,
          FontWeight.values[(spec['fontWeight'] as int) ~/ 100 - 1],
          reason: '$name fontWeight',
        );
      });
    }

    checkStyle('display', SaloniTextStyles.display);
    checkStyle('title-1', SaloniTextStyles.title1);
    checkStyle('title-2', SaloniTextStyles.title2);
    checkStyle('title-3', SaloniTextStyles.title3);
    checkStyle('body-lg', SaloniTextStyles.bodyLg);
    checkStyle('body', SaloniTextStyles.body);
    checkStyle('body-strong', SaloniTextStyles.bodyStrong);
    checkStyle('label', SaloniTextStyles.label);
    checkStyle('caption', SaloniTextStyles.caption);
    checkStyle('time-hero', SaloniTextStyles.timeHero);
    checkStyle('time', SaloniTextStyles.time);
    checkStyle('stat', SaloniTextStyles.stat);
    checkStyle('code', SaloniTextStyles.code);
  });
}
