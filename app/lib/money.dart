// Display helpers only. All maths happens on the backend.

const _zeroDecimal = {'JPY', 'KRW', 'VND', 'CLP', 'ISK', 'UGX', 'XAF', 'XOF', 'PYG', 'RWF'};
const _symbols = {'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'NGN': '₦', 'IDR': 'Rp ', 'BRL': 'R\$ '};

int decimalsFor(String currency) => _zeroDecimal.contains(currency) ? 0 : 2;

String _group(String digits, bool indian) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final size = indian ? 2 : 3;
  final parts = <String>[];
  while (rest.length > size) {
    parts.insert(0, rest.substring(rest.length - size));
    rest = rest.substring(0, rest.length - size);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String formatMoney(int minor, String currency) {
  final neg = minor < 0;
  final abs = minor.abs();
  final d = decimalsFor(currency);
  final unit = d == 0 ? 1 : 100;
  final major = _group('${abs ~/ unit}', currency == 'INR');
  final frac = abs % unit;
  final fracStr = d == 0 || frac == 0 ? '' : '.${frac.toString().padLeft(2, '0')}';
  final sym = _symbols[currency] ?? '$currency ';
  return '${neg ? '-' : ''}$sym$major$fracStr';
}

/// "450" or "450.5" -> minor units; null if not a positive amount.
int? parseMinor(String text, String currency) {
  final clean = text.replaceAll(RegExp(r'[^\d.]'), '');
  final v = double.tryParse(clean);
  if (v == null || v <= 0) return null;
  final d = decimalsFor(currency);
  return (v * (d == 0 ? 1 : 100)).round();
}

String majorText(int minor, String currency) {
  final d = decimalsFor(currency);
  if (d == 0) return '$minor';
  final s = (minor / 100).toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

const kindLabels = {
  'credit_given': 'Credit given',
  'payment_received': 'Payment received',
  'cash_sale': 'Cash sale',
  'expense': 'Expense',
};
