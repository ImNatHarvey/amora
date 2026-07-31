import 'package:go_router/go_router.dart';

import '../features/dev/token_gallery_screen.dart';
import '../features/home/home_screen.dart';

/// Route paths, named so no screen has to hardcode a string literal.
abstract final class Routes {
  static const home = '/';
  static const devTokens = '/dev/tokens';
}

/// The app's single [GoRouter] instance.
///
/// Every navigation in Amora goes through this table (CLAUDE.md conventions);
/// screens never construct a `MaterialPageRoute` directly. Real product routes
/// arrive with their phases — Phase 0 only needs enough shell to prove the app
/// boots and navigates on a device.
final router = GoRouter(
  initialLocation: Routes.home,
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: Routes.devTokens,
      builder: (context, state) => const TokenGalleryScreen(),
    ),
  ],
);
