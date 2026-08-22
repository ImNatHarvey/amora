import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The three top-level destinations, and the bar that switches between them.
///
/// ## Why three, and why not four
///
/// Feed is the fourth and arrives at **Phase 7**, not before: an empty tab makes
/// the app look dead, and Phase 7 is a filtered list rather than a community
/// feed (`CLAUDE.md`'s not-building list). It is deliberately not stubbed here —
/// a disabled or empty destination is worse than an absent one.
///
/// Three is also the floor. Material puts the minimum at three destinations, so
/// Profile and the bar shipped together rather than the bar arriving first with
/// Plan and Memories alone.
///
/// ## Why `StatefulShellRoute.indexedStack`
///
/// Each branch keeps its own `Navigator` and its own state, so switching tabs
/// away from a half-finished conversation and back does not reset it. The
/// alternative — one navigator and a plain `NavigationBar` — rebuilds the
/// destination every time, which would throw away an in-flight intake and cost
/// a model call to recover.
///
/// Detail screens (`/plan/:id`, `/place/:id`, `/plan-request`) sit **outside**
/// the shell on purpose: they are not destinations, and Material's guidance is
/// that the bar persists across top-level destinations, not over every screen.
class AmoraShell extends StatelessWidget {
  const AmoraShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the destination you are already on returns to its root,
          // which is what every Material app does and what a user reaches for
          // when they are three screens deep and want out.
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_calendar_outlined),
            selectedIcon: Icon(Icons.edit_calendar),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined),
            selectedIcon: Icon(Icons.photo_album),
            label: 'Memories',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
