import 'package:intl/intl.dart';

// Money is stored as integer paise (₹1 = 100 paise) to avoid rounding errors.

final NumberFormat _inrWithPaise =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final NumberFormat _inrWhole =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// 25000 -> "₹250", 25050 -> "₹250.50", 10000000 -> "₹1,00,000"
String formatPaise(int paise) => paise % 100 == 0
    ? _inrWhole.format(paise ~/ 100)
    : _inrWithPaise.format(paise / 100);

/// "250.5" -> 25050. Returns null for empty, invalid, zero or negative input.
int? parseRupeesToPaise(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0 || value > 10000000) return null;
  return (value * 100).round();
}

/// 25050 -> "250.50", 25000 -> "250" (for pre-filling text fields).
String paiseToInput(int paise) =>
    paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);

final DateFormat _day = DateFormat('d MMM yyyy');
final DateFormat _time = DateFormat('h:mm a');
final DateFormat _month = DateFormat('MMMM yyyy');

String formatTime(DateTime d) => _time.format(d);
String formatMonth(DateTime d) => _month.format(d);
String formatDateTime(DateTime d) => '${_day.format(d)}, ${_time.format(d)}';

/// "Today", "Yesterday" or "27 Sep 2026".
String formatDayHeader(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _day.format(d);
}
