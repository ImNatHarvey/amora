import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../data/profiles_repository.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/dev/token_gallery_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/onboarding/resource_picker_screen.dart';
import '../features/plan_request/plan_request_screen.dart';
import 'auth_refresh.dart';

/// Route paths, so no screen hardcodes a string literal.
abstract final class Routes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingResources = '/onboarding/resources';
  static const plan = '/plan';
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
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
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
        path: Routes.plan,
        builder: (context, state) => const PlanRequestScreen(),
      ),
      GoRoute(
        path: Routes.devTokens,
        builder: (context, state) => const TokenGalleryScreen(),
      ),
    ],
  );
});
