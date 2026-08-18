import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_client_provider.dart';
import '../theme/app_tokens.dart';

/// The one-time work the app must finish before any screen can talk to Supabase.
///
/// This is deliberately *not* awaited inside `main()`. Doing that held the first
/// frame until Supabase finished initialising — around 20 seconds on a cold
/// emulator — during which the device showed a blank system splash. As a
/// provider it runs while the themed UI is already on screen, and a failure
/// becomes retryable instead of fatal.
final appStartupProvider = FutureProvider<void>((ref) => initialiseSupabase());

/// Shown while [appStartupProvider] is still running.
///
/// Deliberately *not* placed inside `MaterialApp.router`'s `builder`: that
/// builder runs after `routerConfig` is evaluated, and building the router
/// touches `Supabase.instance` — which throws until initialisation finishes.
/// The gate has to sit above the router, so `AmoraApp` switches on the startup
/// state and only constructs the router once it has data.
///
/// ## The animation, and why it is this one
///
/// `02-design-system.md` §6 says never animate for delight alone. A splash
/// animation is delight, so it is recorded there as a named exception rather
/// than left as a contradiction.
///
/// **The binding constraint is interruption, not duration.** `AmoraApp` swaps
/// this widget out the moment startup resolves, and a warm start is well under
/// a second — so any animation is *cut off* rather than played. It therefore
/// has to look deliberate at every frame it might die on. A fade-and-rise does;
/// a draw-on or a scale-then-crossfade both look broken when killed halfway.
///
/// Holding the splash for a minimum duration would remove the problem and was
/// rejected: it delays startup, which is the one thing this whole file exists
/// to avoid.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key});

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// The curve, built once. A `CurvedAnimation` holds a listener on its parent,
  /// so constructing one inside `build` leaks a subscription every frame and
  /// trips Flutter's own dispose diagnostics under a leak-tracking test run.
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _controller,
    curve: Easing.emphasizedDecelerate,
  );

  /// Whether the tween has been started or skipped. Reduced motion is read from
  /// `MediaQuery`, which is not available in `initState`, so the decision
  /// happens on the first `didChangeDependencies` instead.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Respect the OS reduced-motion setting (§6). Jumping to the end state is
    // not "no splash" — it is the same screen, arrived at instantly.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _eased,
              builder: (context, child) => Opacity(
                opacity: _eased.value,
                // Rises by one `md` step. The offset is a token multiple rather
                // than a literal, so the motion stays on the same 4pt scale as
                // the spacing around it.
                child: Transform.translate(
                  offset: Offset(0, tokens.md * (1 - _eased.value)),
                  child: child,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _MascotPlaceholder(),
                  SizedBox(height: tokens.md),
                  Text('Amora', style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
            SizedBox(height: tokens.xl),
            // Not animated, and deliberately outside the fade: it reports real
            // work, so it must not wait on a decorative curve to appear.
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

/// Stands in for the mascot until the art lands.
///
/// Kept as its own widget so swapping it is one file and one class, and kept
/// obviously generic so nobody mistakes it for the final mark. Sized from
/// [AmoraTokens] rather than a literal, and it scales with the icon theme, so
/// it survives 1.3× font scale without a second layout pass.
class _MascotPlaceholder extends StatelessWidget {
  const _MascotPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Container(
      padding: EdgeInsets.all(tokens.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: tokens.xxl,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// Startup failure is almost always a missing or incomplete `.env`, so the
/// message is shown verbatim rather than replaced with something friendlier.
class StartupFailure extends StatelessWidget {
  const StartupFailure({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Amora could not start',
                style: theme.textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.sm),
              Text(message, style: theme.textTheme.bodyLarge),
              SizedBox(height: tokens.lg),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
