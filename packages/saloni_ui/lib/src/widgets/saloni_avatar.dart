import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_typography.dart';

enum SaloniAvatarTone { primary, steel }

/// صورة رمزية بالأحرف الأولى — `Avatar` في `index.d.ts`.
class SaloniAvatar extends StatelessWidget {
  const SaloniAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.tone = SaloniAvatarTone.primary,
  });

  final String name;
  final double size;
  final SaloniAvatarTone tone;

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '';
    final first = words.first.characters.first;
    final second = words.length > 1 && words[1].isNotEmpty
        ? words[1].characters.first
        : '';
    return '$first$second';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final bg = tone == SaloniAvatarTone.steel ? c.steelSoft : c.primarySoft;
    final fg = tone == SaloniAvatarTone.steel ? c.steel : c.primary;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          _initials(name),
          style: TextStyle(
            fontFamily: SaloniFonts.displayFamily,
            fontWeight: FontWeight.w600,
            fontSize: (size * 0.38).roundToDouble(),
            color: fg,
          ),
        ),
      ),
    );
  }
}
