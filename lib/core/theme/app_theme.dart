import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Deep ledger green: calm, money-related, readable in light and dark.
  static const Color seed = Color(0xFF1B5E4B);

  /// Amount colours used across the app.
  static const Color expense = Color(0xFFC62828);
  static const Color income = Color(0xFF2E7D32);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
