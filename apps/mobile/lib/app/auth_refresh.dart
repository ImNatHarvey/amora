import 'package:flutter/foundation.dart';

/// Tells GoRouter to re-run its `redirect`.
///
/// GoRouter takes a [Listenable] for `refreshListenable`, but the things that
/// should trigger a re-check are a Supabase stream (sign in, sign out) and a
/// Riverpod provider (the profile). This is the small adapter between them,
/// written by hand rather than pulling in a dependency for it.
class RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
