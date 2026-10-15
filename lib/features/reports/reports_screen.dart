import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ui.dart';
import '../../core/utils/formatters.dart';
import '../categories/category.dart';
import '../categories/default_categories.dart';
import 'chart_palette.dart';
import 'report_data.dart';

/// Where money went and came from, for a month or a year.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final report = ref.watch(reportProvider);
    final flow = ref.watch(monthlyFlowProvider).valueOrNull;
    final categories = ref.watch(categoryMapProvider);
    final r = report.valueOrNull;

    void setRange(ReportRange next) => ref.read(reportRangeProvider.notifier).state = next;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _PeriodBar(range: range, onChanged: setRange),
          if (report.hasError)
            Padding(
              padding: const EdgeInsets.all(kGutter),
              child: Text('Could not load the report: ${report.error}'),
            ),
          if (r != null) ...[
            _Overview(report: r),
            if (r.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: 'Nothing recorded in this period',
                  message: 'Payments you add or that are detected show up here.',
                ),
              ),
            if (r.spending.isNotEmpty) ...[
              const SectionHeader('Where your money went'),
              DonutCard(
                slices: r.spending,
                categories: categories,
                caption: 'Spent',
              ),
            ],
            if (r.receiving.isNotEmpty) ...[
              const SectionHeader('Where your money came from'),
              DonutCard(
                slices: r.receiving,
                categories: categories,
                caption: 'Received',
              ),
            ],
            if (flow != null && flow.any((m) => m.inPaise > 0 || m.outPaise > 0)) ...[
              SectionHeader(range.year ? 'Each month of ${range.anchor.year}' : 'Last 6 months'),
              FlowBars(months: flow),
            ],
            if (r.topPayees.isNotEmpty) ...[
              const SectionHeader('Top places you paid'),
              _TopPayees(payees: r.topPayees, total: r.spentPaise),
            ],
          ],
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.range, required this.onChanged});

  final ReportRange range;
  final ValueChanged<ReportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    // Short month ("Oct 2026") so it fits beside the Month / Year pills.
    final label = range.year ? '${range.anchor.year}' : DateFormat('MMM yyyy').format(range.anchor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter - 4, 0, kGutter - 4, 4),
      child: Row(
        children: [
          Pill(
            label: 'Month',
            selected: !range.year,
            onTap: () {
              final now = DateTime.now();
              final anchor = range.anchor.year == now.year ? DateTime(now.year, now.month) : DateTime(range.anchor.year, 12);
              onChanged(ReportRange(anchor: anchor, year: false));
            },
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Year',
            selected: range.year,
            onTap: () => onChanged(ReportRange(anchor: DateTime(range.anchor.year), year: true)),
          ),
          const Spacer(),
          IconButton(
            tooltip: range.year ? 'Previous year' : 'Previous month',
            onPressed: () => onChanged(range.shift(-1)),
            icon: Icon(Icons.chevron_left, color: p.muted),
          ),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
          ),
          IconButton(
            tooltip: range.year ? 'Next year' : 'Next month',
            onPressed: range.isCurrent ? null : () => onChanged(range.shift(1)),
            icon: Icon(Icons.chevron_right, color: range.isCurrent ? p.line : p.muted),
          ),
        ],
      ),
    );
  }
}

/// Money out and money in as two numbers: a two-slice pie would hide the
/// difference these show exactly.
class _Overview extends StatelessWidget {
  const _Overview({required this.report});

  final PeriodReport report;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final net = report.incomePaise - report.spentPaise;

    Widget figure(String label, int paise, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.bodySmall),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatPaise(paise),
                  style: t.headlineMedium?.copyWith(color: color, fontFeatures: kTabular),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              figure('Money out', report.spentPaise, p.moneyOut),
              const SizedBox(width: 16),
              figure('Money in', report.incomePaise, p.moneyIn),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            net >= 0
                ? 'You saved ${formatPaise(net)}'
                : 'You spent ${formatPaise(-net)} more than you received',
            style: t.bodyMedium?.copyWith(color: net >= 0 ? p.ink : p.attention),
          ),
          if (report.paidBackPaise > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Friends paid you back ${formatPaise(report.paidBackPaise)} (not counted as money in)',
                style: t.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// A pie (donut) of categories: the five largest and "Everything else".
/// Tap a slice or a row to see its amount in the middle.
class DonutCard extends StatefulWidget {
  const DonutCard({
    super.key,
    required this.slices,
    required this.categories,
    required this.caption,
  });

  final List<Slice> slices;
  final Map<String, TxnCategory> categories;
  final String caption;

  static const int shown = 5;

  @override
  State<DonutCard> createState() => _DonutCardState();
}

class _DonutCardState extends State<DonutCard> {
  int? _selected;

  @override
  void didUpdateWidget(DonutCard old) {
    super.didUpdateWidget(old);
    if (old.slices != widget.slices) _selected = null;
  }

  String _name(String? id) {
    if (id == null) return 'Not categorized';
    if (id == splitSettlementId) return 'Paid back by friends';
    return widget.categories[id]?.name ?? 'Other';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final total = widget.slices.fold<int>(0, (s, x) => s + x.paise);
    final top = widget.slices.take(DonutCard.shown).toList();
    final rest = widget.slices.skip(DonutCard.shown).fold<int>(0, (s, x) => s + x.paise);

    final segments = <_Segment>[
      for (var i = 0; i < top.length; i++)
        _Segment(
          name: _name(top[i].categoryId),
          paise: top[i].paise,
          color: ChartPalette.slot(context, i),
          icon: top[i].categoryId == null ? Icons.help_outline : widget.categories[top[i].categoryId]?.icon,
        ),
      if (rest > 0)
        _Segment(name: 'Everything else', paise: rest, color: ChartPalette.other(context), icon: Icons.more_horiz),
    ];
    final sel = _selected != null && _selected! < segments.length ? segments[_selected!] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGutter),
      child: Column(
        children: [
          Semantics(
            label: '${widget.caption} ${formatPaise(total)}: '
                '${segments.map((s) => '${s.name} ${formatPaise(s.paise)}').join(', ')}',
            excludeSemantics: true,
            child: SizedBox(
              width: 220,
              height: 220,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final i = _hit(d.localPosition, const Size(220, 220), segments, total);
                  setState(() => _selected = i == _selected ? null : i);
                },
                child: CustomPaint(
                  painter: _DonutPainter(
                    segments: segments,
                    total: total,
                    selected: _selected,
                    gapColor: p.canvas,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(44),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sel?.name ?? widget.caption,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatPaise(sel?.paise ?? total),
                              style: t.titleLarge?.copyWith(fontFeatures: kTabular),
                            ),
                          ),
                          if (sel != null)
                            Text(
                              '${(sel.paise * 100 / math.max(1, total)).round()}%',
                              style: t.bodySmall?.copyWith(fontFeatures: kTabular),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < segments.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selected = i == _selected ? null : i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: segments[i].color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (segments[i].icon != null) ...[
                      Icon(segments[i].icon, size: 18, color: p.muted),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        segments[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(
                          fontWeight: i == _selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(segments[i].paise * 100 / math.max(1, total)).round()}%',
                        textAlign: TextAlign.right,
                        style: t.bodySmall?.copyWith(fontFeatures: kTabular),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 84),
                      child: Text(
                        formatPaise(segments[i].paise),
                        textAlign: TextAlign.right,
                        style: t.titleSmall?.copyWith(fontFeatures: kTabular),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Which segment is under [pos], or null for the hole or outside.
  static int? _hit(Offset pos, Size size, List<_Segment> segments, int total) {
    final c = size.center(Offset.zero);
    final v = pos - c;
    final r = v.distance;
    final outer = size.shortestSide / 2;
    if (r > outer || r < outer - _DonutPainter.thickness - 8) return null;
    var angle = math.atan2(v.dy, v.dx) + math.pi / 2; // 0 at the top, clockwise
    if (angle < 0) angle += 2 * math.pi;
    var start = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final sweep = 2 * math.pi * segments[i].paise / math.max(1, total);
      if (angle >= start && angle < start + sweep) return i;
      start += sweep;
    }
    return null;
  }
}

class _Segment {
  const _Segment({required this.name, required this.paise, required this.color, this.icon});

  final String name;
  final int paise;
  final Color color;
  final IconData? icon;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.selected,
    required this.gapColor,
  });

  final List<_Segment> segments;
  final int total;
  final int? selected;
  final Color gapColor;

  static const double thickness = 26;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || segments.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - thickness / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < segments.length; i++) {
      final sweep = 2 * math.pi * segments[i].paise / total;
      final isSel = selected == i;
      final dim = selected != null && !isSel;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? thickness + 6 : thickness
        ..color = dim ? segments[i].color.withValues(alpha: 0.35) : segments[i].color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
    // 2px gaps between slices, in the background colour.
    if (segments.length > 1) {
      final gap = Paint()
        ..color = gapColor
        ..strokeWidth = 2.5;
      var a = -math.pi / 2;
      for (final s in segments) {
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          center + dir * (radius - thickness / 2 - 4),
          center + dir * (radius + thickness / 2 + 4),
          gap,
        );
        a += 2 * math.pi * s.paise / total;
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segments != segments || old.selected != selected || old.total != total || old.gapColor != gapColor;
}

/// Money out and money in per month, side by side. Tap a month for its numbers.
class FlowBars extends StatefulWidget {
  const FlowBars({super.key, required this.months});

  final List<MonthFlow> months;

  @override
  State<FlowBars> createState() => _FlowBarsState();
}

class _FlowBarsState extends State<FlowBars> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final months = widget.months;
    final maxValue = months.fold<int>(0, (m, x) => math.max(m, math.max(x.inPaise, x.outPaise)));
    final sel = _selected == null ? null : months[_selected!];
    final short = DateFormat('MMM');
    const height = 130.0;

    Widget bar(int value, Color color) => Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: maxValue == 0 ? 0 : math.max(value == 0 ? 0 : 3, height * value / maxValue).toDouble(),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ),
        );

    Widget key(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(label, style: t.bodySmall),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              key(p.moneyOut, 'Money out'),
              const SizedBox(width: 16),
              key(p.moneyIn, 'Money in'),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            child: sel == null
                ? Text('Tap a month to see its numbers', style: t.bodySmall)
                : Text.rich(TextSpan(children: [
                    TextSpan(text: '${formatMonth(sel.month)}   ', style: t.labelMedium),
                    TextSpan(text: 'Out ${formatPaise(sel.outPaise)}   ', style: t.bodySmall?.copyWith(color: p.ink, fontFeatures: kTabular)),
                    TextSpan(text: 'In ${formatPaise(sel.inPaise)}', style: t.bodySmall?.copyWith(color: p.moneyIn, fontFeatures: kTabular)),
                  ])),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: months
                .map((m) => '${formatMonth(m.month)}: out ${formatPaise(m.outPaise)}, in ${formatPaise(m.inPaise)}')
                .join('. '),
            excludeSemantics: true,
            child: SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < months.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = _selected == i ? null : i),
                        child: Opacity(
                          opacity: _selected == null || _selected == i ? 1 : 0.4,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: months.length > 6 ? 3 : 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                bar(months[i].outPaise, p.moneyOut),
                                const SizedBox(width: 2),
                                bar(months[i].inPaise, p.moneyIn),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: p.line),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final m in months)
                Expanded(
                  child: Text(
                    months.length > 6 ? short.format(m.month).substring(0, 1) : short.format(m.month),
                    textAlign: TextAlign.center,
                    style: t.labelSmall?.copyWith(color: p.muted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopPayees extends StatelessWidget {
  const _TopPayees({required this.payees, required this.total});

  final List<PayeeTotal> payees;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Group(
      dividerIndent: 16,
      children: [
        for (final payee in payees)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(payee.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontSize: 15)),
                      Text(
                        payee.count == 1 ? '1 payment' : '${payee.count} payments',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatPaise(payee.paise), style: t.titleSmall?.copyWith(fontSize: 15, fontFeatures: kTabular)),
                    Text(
                      '${(payee.paise * 100 / math.max(1, total)).round()}% of spending',
                      style: t.bodySmall?.copyWith(color: p.muted, fontFeatures: kTabular),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
