import 'package:flutter_test/flutter_test.dart';
import 'package:sayledger/money.dart';

void main() {
  test('money formatting', () {
    expect(formatMoney(45000, 'INR'), '₹450');
    expect(formatMoney(12345678, 'INR'), '₹1,23,456.78');
    expect(formatMoney(150050, 'USD'), '\$1,500.50');
    expect(formatMoney(500, 'JPY'), '¥500');
    expect(parseMinor('450.5', 'INR'), 45050);
    expect(parseMinor('0', 'INR'), null);
    expect(majorText(45000, 'INR'), '450');
  });
}
