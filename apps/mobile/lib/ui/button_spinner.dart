import 'package:flutter/material.dart';

/// The spinner that replaces a button's label while it is working.
///
/// Shared because it was written seven times — in `auth_form`,
/// `profile_setup_screen`, `resource_picker_screen`, `add_stop_screen`,
/// `save_plan_button`, `preferences_screen` and twice in
/// `plan_request_screen` — each time as a bare `SizedBox.square(dimension: 20)`
/// around a `CircularProgressIndicator(strokeWidth: 2)`. Seven copies of two
/// magic numbers is seven chances for one of them to drift, and a spinner that
/// is a different size on one screen is the kind of difference nobody can name
/// but everybody can see.
///
/// The size is deliberately **not** a spacing token. It is component sizing, not
/// layout rhythm, and it belongs to the one widget that owns it — the same
/// reasoning `PlanMap` uses for its own preferred height.
///
/// A button keeps its size while it works, because the label it replaces is
/// wider than this: swapping in something smaller would make the button shrink
/// under the finger that just pressed it.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  /// Sized to sit inside a button's text line without changing its height.
  static const double _diameter = 20;

  /// Thin, because at this diameter Material's default stroke reads as a solid
  /// disc rather than as motion.
  static const double _strokeWidth = 2;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: _diameter,
      child: CircularProgressIndicator(strokeWidth: _strokeWidth),
    );
  }
}
