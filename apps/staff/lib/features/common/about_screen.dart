import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import 'shells.dart';
import 'ui.dart';

/// بيانات المطوّر كما طلبها المستخدم (نص ثابت).
abstract final class DeveloperInfo {
  static const company = 'شركة فينكس لتطوير الأنظمة والحلول البرمجية';
  static const programmer = 'برمجة م. عبدالرحمن أبوعون';
  static const phone = '0598789755';
}

/// فتح رابط خارجي (قابل للاستبدال في الاختبارات).
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _defaultOpener(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// «عن التطبيق»: الاسم والإصدار وبيانات المطوّر ورقم الاتصال.
/// يُفتح من «المزيد» (الحلاق) ومن إعدادات المدير (القسم المشترك «الحساب»).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.openUrl = _defaultOpener});

  final UrlOpener openUrl;

  Future<void> _call(BuildContext context) async {
    var ok = false;
    try {
      ok = await openUrl(Uri(scheme: 'tel', path: DeveloperInfo.phone));
    } catch (e, st) {
      debugPrint('[saloni] tel launch failed: $e\n$st');
    }
    if (!ok && context.mounted) {
      toast(context, 'تعذّر فتح الاتصال — الرقم ${DeveloperInfo.phone}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return DetailScaffold(
      title: 'عن التطبيق',
      body: PageBody(children: [
        Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SaloniIcon(SaloniIconName.scissors, color: c.primary, size: 34),
            ),
            const SizedBox(height: 12),
            Text(AppConfig.appName,
                key: const Key('about-app-name'),
                textAlign: TextAlign.center,
                style: SaloniTextStyles.title1.copyWith(color: c.ink)),
            const SizedBox(height: 4),
            Text('تطبيق الطاقم — الحلاق والمدير',
                textAlign: TextAlign.center, style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
          ],
        ),
        const GroupBox(children: [
          ValueRow(first: true, label: 'الإصدار', value: AppConfig.appVersion),
        ]),
        Section(title: 'المطوّر', children: [
          GroupBox(children: [
            const _InfoLine(text: DeveloperInfo.company, first: true, strong: true),
            const _InfoLine(text: DeveloperInfo.programmer),
            _PhoneLine(onTap: () => _call(context)),
          ]),
          SaloniButton(
            key: const Key('about-call'),
            label: 'اتصال بالمطوّر',
            icon: SaloniIconName.phone,
            variant: SaloniButtonVariant.secondary,
            block: true,
            onPressed: () => _call(context),
          ),
        ]),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.text, this.first = false, this.strong = false});
  final String text;
  final bool first;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: BorderDirectional(top: first ? BorderSide.none : BorderSide(color: c.line)),
      ),
      child: Text(
        text,
        style: (strong ? SaloniTextStyles.bodyStrong : SaloniTextStyles.body).copyWith(color: c.ink),
      ),
    );
  }
}

/// «هاتف: 0598789755» — الرقم معزول باتجاه LTR داخل السطر العربي فلا تنقلب
/// أرقامه ولا يقفز النقطتان، وهو قابل للنقر (tel:).
class _PhoneLine extends StatelessWidget {
  const _PhoneLine({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Material(
      color: c.surfaceRaised,
      shape: Border(top: BorderSide(color: c.line)),
      child: InkWell(
        key: const Key('about-phone'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text('هاتف: ', style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
              Text(
                DeveloperInfo.phone,
                key: const Key('about-phone-number'),
                textDirection: TextDirection.ltr,
                style: SaloniTextStyles.bodyStrong.copyWith(
                  color: c.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: c.primary,
                ),
              ),
              const Spacer(),
              SaloniIcon(SaloniIconName.phone, color: c.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
