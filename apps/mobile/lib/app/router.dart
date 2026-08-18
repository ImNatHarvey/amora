import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../data/profiles_repository.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/dev/token_gallery_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/ideas/ideas_screen.dart';
import '../features/intake/intake_screen.dart';
import '../features/memory/memory_timeline_screen.dart';
import '../features/place/place_detail_screen.dart';
import '../features/preferences/preferences_screen.dart';
import '../features/plan/add_stop_screen.dart';
import '../features/plan/plan_detail_screen.dart';
import '../features/plan/saved_plans_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/onboarding/resource_picker_screen.dart';
import '../features/plan_request/plan_request_screen.dart';
import 'auth_refresh.dart';
import 'shell.dart';

/// Route paths, so no screen hardcodes a string literal.
abstract final class Routes {
  /// Where a signed-in, onboarded user lands, and the first tab.
  ///
  /// Was `HomeScreen` until Gate B. That screen's whole content was a column of
  /// buttons, which *was* the navigation — so once the bar existed there was
  /// nothing left for it to do. `/` now redirects here rather than 404ing, for
  /// deep links and for anything still holding the old path.
  static const home = intake;

  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingResources = '/onboarding/resources';
  /// The conversation — Phase 3b, and the intake as of D10. "Plan something"
  /// on home leads here.
  static const intake = '/intake';

  /// The structured intake — budget, origin, time. Renamed from `/plan` when
  /// Phase 4 needed that prefix for saved plans; it is the request, not a plan.
  ///
  /// Still reachable from the conversation, deliberately: it is the fallback
  /// when extraction fails, and the only way to exercise retrieval with no
  /// model in the loop.
  static const planRequest = '/plan-request';
  static const ideas = '/ideas';

  /// The list of saved plans, and one saved plan at `/plan/:id`.
  static const plans = '/plans';
  static const plan = '/plan';

  /// Place detail at `/place/:id`.
  static const place = '/place';

  /// What actually happened — Phase 6's timeline of completed outings.
  static const memories = '/memories';

  /// How the user usually plans. Optional everywhere — nothing gates on it.
  ///
  /// Top level rather than nested under a profile screen because Gate B has not
  /// built one yet. It moves under Profile when the nav arrives.
  static const preferences = '/preferences';

  /// Who you are, what you own, how you usually plan. The third destination.
  static const profile = '/profile';

  static const devTokens = '/dev/tokens';
}

/// Routes reachable without a session.
const _publicRoutes = {Routes.signIn, Routes.signUp, Routes.devTokens};

/// Routes that only make sense while onboarding is unfinished.
const _onboardingRoutes = {Routes.onboardingProfile, Routes.onboardingResources};

/// The app's [GoRouter].
///
/// A provider rather than a top-level final, because `redirect` needs to read
/// the current session and profile. Every navigation in Amora goes through this
/// table (CLAUDE.md conventions).
final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  final refresh = RouterRefresh();
  ref.onDispose(refresh.dispose);

  // Re-evaluate the ladder on sign in and sign out...
  final subscription =
      authRepository.onAuthStateChange.listen((_) => refresh.notify());
  ref.onDispose(subscription.cancel);

  // ...and whenever the profile changes, which is how finishing a step of
  // onboarding advances to the next one.
  ref.listen(currentProfileProvider, (_, _) => refresh.notify());

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    // Synchronous on purpose. An async redirect that awaits the profile leaves
    // GoRouter with nothing to render while it resolves — a black screen. The
    // profile is loaded before the router is built (see AmoraApp), so by the
    // time this runs the value is already in hand.
    redirect: (context, state) {
      final location = state.matchedLocation;

      // Signed out: only the public routes are reachable.
      if (authRepository.currentUserId == null) {
        return _publicRoutes.contains(location) ? null : Routes.signIn;
      }

      // The dev gallery stays reachable in every state — it is a verification
      // surface, not product.
      if (location == Routes.devTokens) return null;

      final profileState = ref.read(currentProfileProvider);

      // Mid-refetch: hold position rather than guessing.
      if (profileState.isLoading) return null;

      final profile = profileState.valueOrNull;

      // Signed in with no profile row should be impossible — the
      // on_auth_user_created trigger writes it. If it happens anyway, sending
      // them to setup is better than stranding them on the sign-in screen.
      if (profile == null) {
        return location == Routes.onboardingProfile
            ? null
            : Routes.onboardingProfile;
      }

      if (!profile.hasCity) {
        return location == Routes.onboardingProfile
            ? null
            : Routes.onboardingProfile;
      }

      if (!profile.isOnboarded) {
        return location == Routes.onboardingResources
            ? null
            : Routes.onboardingResources;
      }

      // Fully set up — auth and onboarding routes are behind them now.
      if (_publicRoutes.contains(location) ||
          _onboardingRoutes.contains(location)) {
        return Routes.home;
      }

      return null;
    },
    routes: [
      // The three top-level destinations. Everything else is either pre-session
      // (auth, onboarding) or a detail screen pushed over the bar.
      //
      // Ideas and saved plans live *inside* the Plan branch rather than outside
      // the shell: they are places you go while planning, so the bar stays and
      // the back stack belongs to that tab. Plan detail and place detail sit
      // outside, because Material persists the bar across destinations, not
      // across every screen.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AmoraShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              // Not listed in _publicRoutes or _onboardingRoutes, so the ladder
              // above already requires a session and finished onboarding — the
              // resource picker has to have run before retrieval can filter on
              // what the user owns.
              GoRoute(
                path: Routes.intake,
                builder: (context, state) => const IntakeScreen(),
              ),
              GoRoute(
                path: Routes.ideas,
                builder: (context, state) => const IdeasScreen(),
              ),
              GoRoute(
                path: Routes.plans,
                builder: (context, state) => const SavedPlansScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.memories,
                builder: (context, state) => const MemoryTimelineScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
              GoRoute(
                path: Routes.preferences,
                builder: (context, state) => const PreferencesScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: Routes.onboardingProfile,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: Routes.onboardingResources,
        builder: (context, state) => const ResourcePickerScreen(),
      ),
      // Not listed in _publicRoutes or _onboardingRoutes, so the ladder above
      // already requires a session and finished onboarding to reach it — the
      // resource picker has to have run before retrieval can filter on what
      // the user owns.
      GoRoute(
        path: Routes.intake,
        builder: (context, state) => const IntakeScreen(),
      ),
      GoRoute(
        path: Routes.planRequest,
        builder: (context, state) => const PlanRequestScreen(),
      ),
      // Saved plan and place detail. Both take an id and both are behind the
      // same ladder; RLS is what actually decides whether the row comes back,
      // so a guessed id is an empty screen rather than a leak.
      GoRoute(
        path: '${Routes.plan}/:id',
        builder: (context, state) =>
            PlanDetailScreen(planId: state.pathParameters['id']!),
        routes: [
          // Nested, so the plan id is in the path rather than carried in
          // state — the screen has to know which plan it is adding to, and a
          // deep link that lost it would be a dead end.
          GoRoute(
            path: 'add-stop',
            builder: (context, state) =>
                AddStopScreen(planId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '${Routes.place}/:id',
        builder: (context, state) =>
            PlaceDetailScreen(placeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.devTokens,
        builder: (context, state) => const TokenGalleryScreen(),
      ),
      // `/` no longer has a screen. Kept as a redirect rather than deleted so a
      // deep link, a saved shortcut or an older build's initial location lands
      // somewhere real instead of on GoRouter's error page.
      GoRoute(path: '/', redirect: (context, state) => Routes.intake),
    ],
  );
});
