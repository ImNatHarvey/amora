/// Turning stored values into text a person reads.
///
/// Pure functions with no widget dependency, like `manila_time.dart` beside it,
/// so the rules they encode can be tested directly instead of only through
/// whichever screen happens to call them.
library;

/// `₱180`, or `₱180.50` when the centavos are not round.
///
/// Money is integer centavos everywhere else in the app (CLAUDE.md
/// conventions); this is the single point where it becomes text.
///
/// **The [zeroIsFree] rule was learned the hard way**, by reading three wrong
/// sentences on a device: "places ₱200 · fares free", "budget free", and "none
/// fit free". ₱0 reads as *free* wherever it is **the price of something** — a
/// place, a leg, a plan total — which is the design system's position that free
/// is good news and never muted (`docs/02-design-system.md` §2). It reads as
/// **₱0** wherever it is an addend in a breakdown or a constraint being echoed
/// back, because there it names a category rather than an amount.
///
/// This lived in two screens as a byte-identical copy until the Phase 3 review.
/// That mattered more than ordinary duplication: it is a correctness rule about
/// what the product says about money, and two copies could be fixed apart.
String pesos(int cents, {bool zeroIsFree = true}) {
  if (cents == 0) return zeroIsFree ? 'free' : '₱0';
  final whole = cents ~/ 100;
  final remainder = cents % 100;
  return remainder == 0
      ? '₱$whole'
      : '₱$whole.${remainder.toString().padLeft(2, '0')}';
}

/// `450 m`, or `1.2 km` past a kilometre.
///
/// Distances are stored as integer metres. Sub-kilometre precision matters
/// here: 800 m is the walk threshold, so the difference between 780 and 820 is
/// the difference between a free leg and a fare.
String distance(int metres) =>
    metres < 1000 ? '$metres m' : '${(metres / 1000).toStringAsFixed(1)} km';

/// `7:00 PM` — a Manila wall-clock time, for a person rather than a log.
///
/// [manilaLocal] must already be Manila local, which is what `toManila`
/// returns. This does no conversion of its own: a formatter that also shifted
/// timezones would be two rules in one function, and the one it would hide is
/// the one worth eight hours of confusion.
///
/// Separate from `formatManila`, which prints the date too and describes itself
/// as debugging-grade. That is right for a plan's heading and wrong on a stop,
/// where the date is already stated once above and repeating it per row buries
/// the only part that differs.
String formatManilaTime(DateTime manilaLocal) {
  final hour24 = manilaLocal.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = manilaLocal.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
}

/// `45 min`, `2h`, or `1h 30m`.
String duration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
