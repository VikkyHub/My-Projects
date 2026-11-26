import 'package:intl/intl.dart';

final _whole = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _exact = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// 149900 → "₹1,499" · 12345678 → "₹1,23,456.78" (Indian digit grouping). Money is always paise on the wire.
String formatPaise(num? paise) {
  if (paise == null) return '—';
  final p = paise.round();
  return p % 100 == 0 ? _whole.format(p ~/ 100) : _exact.format(p / 100);
}

/// Rupees typed by a vendor ("1,499.50") → paise. Returns null if not a number.
int? parseRupeesToPaise(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
  final v = double.tryParse(cleaned);
  return v == null ? null : (v * 100).round();
}
