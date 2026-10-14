import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colours the app uses by meaning rather than by Material role.
///
/// Money out is shown in plain ink (spending is normal, not an error);
/// money in is green. Marigold is the one accent and is kept for things that
/// want attention: the add button, "needs a category", and today.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.raised,
    required this.sunken,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.attention,
    required this.moneyIn,
    required this.moneyOut,
    required this.bar,
  });

  /// Screen background.
  final Color canvas;

  /// Grouped lists and sheets that sit on the canvas.
  final Color raised;

  /// Inputs and tracks set into a raised surface.
  final Color sunken;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;

  /// Marigold.
  final Color accent;
  final Color onAccent;

  /// Text that needs attention (readable marigold-brown on light).
  final Color attention;
  final Color moneyIn;
  final Color moneyOut;

  /// Daily spending bars on the home screen.
  final Color bar;

  static const light = AppPalette(
    canvas: Color(0xFFF4F5F7),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFEDEFF2),
    ink: Color(0xFF15171A),
    muted: Color(0xFF6E737C),
    faint: Color(0xFFA3A8B0),
    line: Color(0xFFE4E6EA),
    accent: Color(0xFFF5B301),
    onAccent: Color(0xFF15171A),
    attention: Color(0xFF8A5A00),
    moneyIn: Color(0xFF0B8A5A),
    moneyOut: Color(0xFF15171A),
    bar: Color(0xFFCDD1D7),
  );

  static const dark = AppPalette(
    canvas: Color(0xFF0D0E10),
    raised: Color(0xFF18191C),
    sunken: Color(0xFF222428),
    ink: Color(0xFFF2F3F5),
    muted: Color(0xFF9AA0A8),
    faint: Color(0xFF666B73),
    line: Color(0xFF2A2C31),
    accent: Color(0xFFF5B301),
    onAccent: Color(0xFF15171A),
    attention: Color(0xFFF5C542),
    moneyIn: Color(0xFF3DD598),
    moneyOut: Color(0xFFF2F3F5),
    bar: Color(0xFF3A3D43),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      canvas: l(canvas, other.canvas),
      raised: l(raised, other.raised),
      sunken: l(sunken, other.sunken),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      attention: l(attention, other.attention),
      moneyIn: l(moneyIn, other.moneyIn),
      moneyOut: l(moneyOut, other.moneyOut),
      bar: l(bar, other.bar),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// Amounts line up in columns.
const List<FontFeature> kTabular = [FontFeature.tabularFigures()];

class AppTheme {
  AppTheme._();

  static const String font = 'Manrope';

  /// Corner radius for grouped lists and sheets.
  static const double radius = 20;

  /// Corner radius for icon tiles and inputs.
  static const double tileRadius = 12;

  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static TextTheme _text(AppPalette p) {
    TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0, Color? c}) =>
        TextStyle(
          fontFamily: font,
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: ls,
          color: c ?? p.ink,
        );
    return TextTheme(
      // Hero amount on Home.
      displayLarge: s(44, FontWeight.w800, h: 1.05, ls: -1.6),
      displayMedium: s(40, FontWeight.w800, h: 1.05, ls: -1.4),
      displaySmall: s(34, FontWeight.w700, h: 1.1, ls: -1.0),
      headlineLarge: s(30, FontWeight.w700, h: 1.15, ls: -0.8),
      headlineMedium: s(26, FontWeight.w700, h: 1.2, ls: -0.6),
      headlineSmall: s(22, FontWeight.w700, h: 1.25, ls: -0.4),
      titleLarge: s(20, FontWeight.w700, h: 1.25, ls: -0.3),
      titleMedium: s(16, FontWeight.w600, h: 1.3, ls: -0.1),
      titleSmall: s(14, FontWeight.w600, h: 1.3),
      bodyLarge: s(16, FontWeight.w500, h: 1.45),
      bodyMedium: s(14, FontWeight.w500, h: 1.45, c: p.ink),
      bodySmall: s(13, FontWeight.w500, h: 1.4, c: p.muted),
      labelLarge: s(14, FontWeight.w600, h: 1.2),
      labelMedium: s(13, FontWeight.w600, h: 1.2),
      labelSmall: s(11, FontWeight.w600, h: 1.2, ls: 0.2),
    );
  }

  static ThemeData _build(AppPalette p, Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: p.ink,
      onPrimary: p.canvas,
      primaryContainer: isDark ? const Color(0xFF1E2A24) : const Color(0xFFE6F4EC),
      onPrimaryContainer: p.ink,
      secondary: p.muted,
      onSecondary: p.canvas,
      secondaryContainer: p.sunken,
      onSecondaryContainer: p.ink,
      tertiary: p.attention,
      onTertiary: p.canvas,
      tertiaryContainer: isDark ? const Color(0xFF2E2507) : const Color(0xFFFFF3CF),
      onTertiaryContainer: p.ink,
      error: isDark ? const Color(0xFFFF8A7A) : const Color(0xFFC4321F),
      onError: p.canvas,
      surface: p.canvas,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceContainerLowest: p.raised,
      surfaceContainerLow: p.raised,
      surfaceContainer: p.raised,
      surfaceContainerHigh: p.sunken,
      surfaceContainerHighest: p.sunken,
      outline: p.faint,
      outlineVariant: p.line,
      inverseSurface: p.ink,
      onInverseSurface: p.canvas,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    final text = _text(p);
    const stadium = StadiumBorder();
    final tileShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(tileRadius));

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: font,
      textTheme: text,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: p.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: p.muted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.sunken,
        hintStyle: text.bodyLarge?.copyWith(color: p.faint),
        labelStyle: text.bodyMedium?.copyWith(color: p.muted),
        floatingLabelStyle: text.bodySmall?.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide(color: p.ink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tileRadius),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(p.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: const WidgetStatePropertyAll(stadium),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
        textStyle: WidgetStatePropertyAll(text.bodyLarge),
        hintStyle: WidgetStatePropertyAll(text.bodyLarge?.copyWith(color: p.faint)),
        constraints: const BoxConstraints(minHeight: 48),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.raised,
        selectedColor: p.ink,
        disabledColor: p.sunken,
        side: BorderSide(color: p.line),
        shape: stadium,
        labelStyle: text.labelLarge?.copyWith(color: p.ink),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: p.canvas),
        iconTheme: IconThemeData(color: p.muted, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        showCheckmark: false,
        checkmarkColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: p.canvas,
          disabledBackgroundColor: p.sunken,
          disabledForegroundColor: p.faint,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: stadium,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: stadium,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          shape: stadium,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.ink : p.raised,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.canvas : p.ink,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.line)),
          shape: const WidgetStatePropertyAll(stadium),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.canvas : p.faint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : p.sunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : p.line,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.canvas),
        side: BorderSide(color: p.faint, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.ink,
        linearTrackColor: p.sunken,
        circularTrackColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: text.labelLarge?.copyWith(color: p.onAccent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: p.sunken,
        indicatorShape: stadium,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? p.ink : p.muted,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontSize: 12,
            color: s.contains(WidgetState.selected) ? p.ink : p.muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.raised,
        showDragHandle: true,
        dragHandleColor: p.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.canvas),
        actionTextColor: p.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.raised,
        headerForegroundColor: p.ink,
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: p.raised),
      popupMenuTheme: PopupMenuThemeData(
        color: p.raised,
        surfaceTintColor: Colors.transparent,
        shape: tileShape,
      ),
    );
  }
}
