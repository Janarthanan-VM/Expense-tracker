/// One slice of a pie: a category (null = not categorized) and its total.
class Slice {
  const Slice({required this.categoryId, required this.paise});

  final String? categoryId;
  final int paise;
}

/// A payee and how much you spent with them.
class PayeeTotal {
  const PayeeTotal({required this.name, required this.paise, required this.count});

  final String name;
  final int paise;
  final int count;
}

/// Money in and out for one calendar month.
class MonthFlow {
  const MonthFlow({required this.month, required this.outPaise, required this.inPaise});

  final DateTime month;
  final int outPaise;
  final int inPaise;
}

/// Everything the Reports screen shows for one period.
class PeriodReport {
  const PeriodReport({
    required this.start,
    required this.end,
    required this.spentPaise,
    required this.incomePaise,
    required this.paidBackPaise,
    required this.spending,
    required this.receiving,
    required this.topPayees,
  });

  final DateTime start;

  /// Exclusive.
  final DateTime end;

  /// Your spending (your share of split bills).
  final int spentPaise;

  /// Money received, not counting friends paying you back.
  final int incomePaise;
  final int paidBackPaise;

  /// Spending by category, largest first.
  final List<Slice> spending;

  /// Money received by category (including "Paid back by friends"), largest first.
  final List<Slice> receiving;
  final List<PayeeTotal> topPayees;

  int get receivedPaise => receiving.fold(0, (sum, s) => sum + s.paise);
  bool get isEmpty => spending.isEmpty && receiving.isEmpty;
}

/// The period the Reports screen shows: a month, or a whole year.
class ReportRange {
  const ReportRange({required this.anchor, required this.year});

  /// First day of the month (or of the year when [year]).
  final DateTime anchor;
  final bool year;

  DateTime get start => year ? DateTime(anchor.year) : DateTime(anchor.year, anchor.month);
  DateTime get end => year ? DateTime(anchor.year + 1) : DateTime(anchor.year, anchor.month + 1);

  ReportRange shift(int delta) => ReportRange(
        anchor: year ? DateTime(anchor.year + delta) : DateTime(anchor.year, anchor.month + delta),
        year: year,
      );

  /// True when moving forward would go past the current period.
  bool get isCurrent {
    final now = DateTime.now();
    return year ? anchor.year >= now.year : (anchor.year > now.year || (anchor.year == now.year && anchor.month >= now.month));
  }

  @override
  bool operator ==(Object other) => other is ReportRange && other.anchor == anchor && other.year == year;

  @override
  int get hashCode => Object.hash(anchor, year);
}
