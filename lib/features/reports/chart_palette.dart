import 'package:flutter/material.dart';

/// Colours for chart slices, in a fixed order checked for colour-blind
/// safety and contrast (light and dark steps of the same eight hues).
/// Category colours elsewhere in the app are chosen for icons, not for
/// telling neighbouring pie slices apart, so charts use these instead.
class ChartPalette {
  ChartPalette._();

  static const List<Color> light = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF6250D6), // violet
    Color(0xFFE34948), // red
  ];

  static const List<Color> dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  /// Neutral for the "Everything else" slice; checked against its
  /// neighbours (the last slot and, around the circle, the first).
  static Color other(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFC3C2B7) : const Color(0xFF52514E);

  /// Slot [i] for the current brightness.
  static Color slot(BuildContext context, int i) {
    final list = Theme.of(context).brightness == Brightness.dark ? dark : light;
    return list[i % list.length];
  }
}
