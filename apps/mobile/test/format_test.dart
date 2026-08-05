import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/util/format.dart';

/// The money-wording rule, tested directly for the first time.
///
/// It was previously reachable only through a widget, and existed as two
/// byte-identical copies in two screens — so a fix to one would have left the
/// other wrong, and no test would have noticed.
void main() {
  group('pesos', () {
    test('whole amounts carry no decimals', () {
      expect(pesos(18000), '₱180');
      expect(pesos(2500), '₱25');
    });

    test('centavos survive when they are not round', () {
      expect(pesos(18050), '₱180.50');
      expect(pesos(18005), '₱180.05');
    });

    test('zero is "free" where it is the price of something', () {
      // A place, a leg, a plan total. The design system's position is that free
      // is good news and never muted (docs 02 §2).
      expect(pesos(0), 'free');
    });

    test('zero is "₱0" where it is an addend or a constraint', () {
      // The three sentences this rule was learned from, on a device:
      // "places ₱200 · fares free", "budget free", "none fit free". Each reads
      // as a category rather than an amount.
      expect(pesos(0, zeroIsFree: false), '₱0');
    });
  });

  group('distance', () {
    test('metres below a kilometre', () {
      expect(distance(132), '132 m');
      // 800 m is the walk threshold, so precision on either side of it is the
      // difference between a free leg and a fare.
      expect(distance(799), '799 m');
      expect(distance(800), '800 m');
    });

    test('kilometres above it, to one decimal', () {
      expect(distance(1000), '1.0 km');
      expect(distance(5400), '5.4 km');
    });
  });

  group('duration', () {
    test('minutes below an hour', () {
      expect(duration(45), '45 min');
    });

    test('whole hours drop the minutes', () {
      expect(duration(120), '2h');
    });

    test('mixed durations keep both', () {
      expect(duration(90), '1h 30m');
    });
  });
}
