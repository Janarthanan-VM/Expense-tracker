import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Small building blocks shared by every screen, so spacing, corners and
/// colours stay consistent.

/// Page side margin.
const double kGutter = 20;

/// Heading above a block of content, with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.padding});

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(kGutter, 28, kGutter - 8, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A rounded raised panel holding related rows, separated by inset lines.
class Group extends StatelessWidget {
  const Group({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: kGutter - 4),
    this.dividerIndent = 72,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: dividerIndent, endIndent: 16, color: p.line));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: margin,
      child: Material(
        color: p.raised,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}

/// Rounded square with a tinted icon (category, payment method, setting).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(AppTheme.tileRadius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: dark ? Color.lerp(color, Colors.white, 0.35) : color),
    );
  }
}

/// Empty or placeholder message, centred in the available space.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: p.faint),
            const SizedBox(height: 16),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Signed amount: "−₹250" in ink for money out, "+₹500" in green for money in.
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.text,
    required this.isIncome,
    this.style,
    this.struck = false,
  });

  final String text;
  final bool isIncome;
  final TextStyle? style;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = style ?? Theme.of(context).textTheme.titleMedium!;
    return Text(
      text,
      maxLines: 1,
      style: base.copyWith(
        color: struck ? p.faint : (isIncome ? p.moneyIn : p.moneyOut),
        decoration: struck ? TextDecoration.lineThrough : null,
        fontFeatures: kTabular,
      ),
    );
  }
}

/// Stadium-shaped filter or choice. Selected = ink with light text.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.canvas : p.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? p.ink : p.raised,
        shape: StadiumBorder(side: BorderSide(color: selected ? p.ink : p.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(icon == null ? 16 : 12, 9, 16, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: selected ? p.canvas : p.muted),
                  const SizedBox(width: 6),
                ],
                Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
