import 'package:flutter/widgets.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Icon-name tokens, mirroring `IconName` in
/// `design/design-system/components/index.d.ts`. Rendered with Phosphor
/// Icons at **regular** weight, as required by the brand book.
enum SaloniIconName {
  scissors,
  clock,
  hourglassMedium,
  user,
  usersThree,
  calendarCheck,
  bellRinging,
  wifiSlash,
  wifiHigh,
  check,
  checkCircle,
  x,
  xCircle,
  caretLeft,
  caretRight,
  plus,
  coins,
  receipt,
  chartBar,
  gearSix,
  qrCode,
  phone,
  lockSimple,
  eye,
  eyeSlash,
  warning,
  info,
  clockCounterClockwise,
  arrowUUpLeft,
  userPlus,
  coffee,
  storefront,
  listNumbers,
  signOut,
  mapPin,
  whatsappLogo,
  instagramLogo,
  navigationArrow,
  image,
  package,
  tag,
}

/// Resolves a [SaloniIconName] to its Phosphor **regular**-weight glyph.
IconData saloniIconData(SaloniIconName name) {
  switch (name) {
    case SaloniIconName.scissors:
      return PhosphorIconsRegular.scissors;
    case SaloniIconName.clock:
      return PhosphorIconsRegular.clock;
    case SaloniIconName.hourglassMedium:
      return PhosphorIconsRegular.hourglassMedium;
    case SaloniIconName.user:
      return PhosphorIconsRegular.user;
    case SaloniIconName.usersThree:
      return PhosphorIconsRegular.usersThree;
    case SaloniIconName.calendarCheck:
      return PhosphorIconsRegular.calendarCheck;
    case SaloniIconName.bellRinging:
      return PhosphorIconsRegular.bellRinging;
    case SaloniIconName.wifiSlash:
      return PhosphorIconsRegular.wifiSlash;
    case SaloniIconName.wifiHigh:
      return PhosphorIconsRegular.wifiHigh;
    case SaloniIconName.check:
      return PhosphorIconsRegular.check;
    case SaloniIconName.checkCircle:
      return PhosphorIconsRegular.checkCircle;
    case SaloniIconName.x:
      return PhosphorIconsRegular.x;
    case SaloniIconName.xCircle:
      return PhosphorIconsRegular.xCircle;
    case SaloniIconName.caretLeft:
      return PhosphorIconsRegular.caretLeft;
    case SaloniIconName.caretRight:
      return PhosphorIconsRegular.caretRight;
    case SaloniIconName.plus:
      return PhosphorIconsRegular.plus;
    case SaloniIconName.coins:
      return PhosphorIconsRegular.coins;
    case SaloniIconName.receipt:
      return PhosphorIconsRegular.receipt;
    case SaloniIconName.chartBar:
      return PhosphorIconsRegular.chartBar;
    case SaloniIconName.gearSix:
      return PhosphorIconsRegular.gearSix;
    case SaloniIconName.qrCode:
      return PhosphorIconsRegular.qrCode;
    case SaloniIconName.phone:
      return PhosphorIconsRegular.phone;
    case SaloniIconName.lockSimple:
      return PhosphorIconsRegular.lockSimple;
    case SaloniIconName.eye:
      return PhosphorIconsRegular.eye;
    case SaloniIconName.eyeSlash:
      return PhosphorIconsRegular.eyeSlash;
    case SaloniIconName.warning:
      return PhosphorIconsRegular.warning;
    case SaloniIconName.info:
      return PhosphorIconsRegular.info;
    case SaloniIconName.clockCounterClockwise:
      return PhosphorIconsRegular.clockCounterClockwise;
    case SaloniIconName.arrowUUpLeft:
      return PhosphorIconsRegular.arrowUUpLeft;
    case SaloniIconName.userPlus:
      return PhosphorIconsRegular.userPlus;
    case SaloniIconName.coffee:
      return PhosphorIconsRegular.coffee;
    case SaloniIconName.storefront:
      return PhosphorIconsRegular.storefront;
    case SaloniIconName.listNumbers:
      return PhosphorIconsRegular.listNumbers;
    case SaloniIconName.signOut:
      return PhosphorIconsRegular.signOut;
    case SaloniIconName.mapPin:
      return PhosphorIconsRegular.mapPin;
    case SaloniIconName.whatsappLogo:
      return PhosphorIconsRegular.whatsappLogo;
    case SaloniIconName.instagramLogo:
      return PhosphorIconsRegular.instagramLogo;
    case SaloniIconName.navigationArrow:
      return PhosphorIconsRegular.navigationArrow;
    case SaloniIconName.image:
      return PhosphorIconsRegular.image;
    case SaloniIconName.package:
      return PhosphorIconsRegular.package;
    case SaloniIconName.tag:
      return PhosphorIconsRegular.tag;
  }
}

/// A directional icon: mirrored under RTL via [SaloniIcon] unless disabled.
class SaloniIcon extends StatelessWidget {
  const SaloniIcon(
    this.name, {
    super.key,
    this.size,
    this.color,
    this.mirrorInRtl = false,
    this.semanticLabel,
  });

  final SaloniIconName name;
  final double? size;
  final Color? color;

  /// عكس الأيقونات الاتجاهية في RTL (mirror).
  final bool mirrorInRtl;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final icon = Icon(
      saloniIconData(name),
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
    if (mirrorInRtl && isRtl) {
      return Transform.flip(flipX: true, child: icon);
    }
    return icon;
  }
}
