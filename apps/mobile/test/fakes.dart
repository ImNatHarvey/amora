import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/plans_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/models/activity.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/models/resource.dart';
import 'package:mobile/models/saved_plan.dart';
import 'package:mobile/models/simple_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-ins for the repositories, so widget tests exercise real
/// screens and real routing without a network or a Supabase client.
///
/// These `implement` rather than extend: from another library only the public
/// API has to be satisfied, so the private client field is not needed.

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.userId});

  String? userId;
  int signOutCount = 0;

  @override
  String? get currentUserId => userId;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();

  @override
  Future<void> signUp({required String email, required String password}) async {
    userId = 'new-user';
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    userId = 'existing-user';
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    userId = null;
  }
}

class FakeProfilesRepository implements ProfilesRepository {
  FakeProfilesRepository({this.profile});

  Profile? profile;

  @override
  Future<Profile?> fetchMine() async => profile;

  @override
  Future<void> updateProfile({String? displayName, String? city}) async {
    final current = profile;
    if (current == null) return;
    profile = Profile(
      id: current.id,
      displayName: displayName ?? current.displayName,
      city: city ?? current.city,
      onboardedAt: current.onboardedAt,
    );
  }

  @override
  Future<void> markOnboarded() async {
    final current = profile;
    if (current == null) return;
    profile = Profile(
      id: current.id,
      displayName: current.displayName,
      city: current.city,
      onboardedAt: DateTime.utc(2026, 7, 31),
    );
  }
}

class FakeResourcesRepository implements ResourcesRepository {
  FakeResourcesRepository({List<Resource>? catalog, Set<String>? owned})
      : catalog = catalog ?? defaultCatalog,
        owned = owned ?? <String>{};

  static const defaultCatalog = <Resource>[
    Resource(id: 'r1', slug: 'picnic-mat', name: 'Picnic mat', category: 'outdoor', icon: 'deck'),
    Resource(id: 'r2', slug: 'tent', name: 'Tent', category: 'outdoor', icon: 'cabin'),
    Resource(id: 'r3', slug: 'board-games', name: 'Board games', category: 'games', icon: 'casino'),
  ];

  final List<Resource> catalog;
  Set<String> owned;

  @override
  Future<List<Resource>> fetchCatalog() async => catalog;

  @override
  Future<Set<String>> fetchMine() async => owned;

  @override
  Future<void> replaceMine(Set<String> resourceIds) async {
    owned = {...resourceIds};
  }
}

class FakeRetrievalRepository implements RetrievalRepository {
  FakeRetrievalRepository({List<OriginArea>? areas, this.plan, this.error})
      : areas = areas ?? defaultAreas;

  static const defaultAreas = <OriginArea>[
    OriginArea(area: 'Poblacion', lat: 14.7966, lng: 120.9268, placeCount: 9),
    OriginArea(area: 'Turo', lat: 14.8003, lng: 120.9218, placeCount: 3),
  ];

  final List<OriginArea> areas;

  /// Returned by [buildSimplePlan]. Null yields an empty plan, which is a real
  /// outcome rather than a failure — nothing open that fits.
  final SimplePlan? plan;

  /// When set, [buildSimplePlan] throws it instead of returning.
  final Object? error;

  int buildCount = 0;

  /// Returned by [activitiesWithin], unfiltered — the fake does no filtering of
  /// its own on purpose. Budget and gear filtering is Postgres's job
  /// (`retrieve_activities`), and a fake that reimplemented it would be testing
  /// the fake. What the widget tests check is what the screen does with a list.
  List<Activity> activities = const [];

  /// Every per-person budget asked for, in centavos, in call order.
  ///
  /// A list rather than a "last value", because the ideas screen makes two
  /// calls per render: the filtered one the user asked for, and an unfiltered
  /// one behind it that counts the whole catalogue so an empty list can say
  /// what it is empty *of*. Recording only the last would silently assert
  /// against the wrong one.
  final activityBudgetsPhpCents = <int>[];

  @override
  Future<List<Activity>> activitiesWithin({
    required int budgetPhpCents,
    required Set<String> ownedResourceIds,
  }) async {
    if (error != null) throw error!;
    activityBudgetsPhpCents.add(budgetPhpCents ~/ RetrievalRepository.partySize);
    return activities;
  }

  @override
  Future<List<OriginArea>> originAreas(String city) async => areas;

  /// Deliberately wider than [areas], mirroring the real split: `known_areas`
  /// includes barangays that have fares but no curated places, and a fake that
  /// returned the same list either way would hide a screen using the wrong one.
  ///
  /// `Wakas` deliberately has no fares, so the "this leg will be unpriced"
  /// warning has something to fire on.
  List<KnownArea> known = const [
    KnownArea(area: 'Bunlo', hasPlaces: true, hasFares: true),
    KnownArea(area: 'Duhat', hasPlaces: false, hasFares: true),
    KnownArea(area: 'Poblacion', hasPlaces: true, hasFares: true),
    KnownArea(area: 'Turo', hasPlaces: true, hasFares: true),
    KnownArea(area: 'Wakas', hasPlaces: false, hasFares: false),
  ];

  @override
  Future<List<KnownArea>> knownAreas(String city) async => known;

  @override
  Future<SimplePlan> buildSimplePlan({
    required String city,
    required int budgetPhpCents,
    required DateTime plannedForUtc,
    required OriginArea origin,
    required Set<String> ownedResourceIds,
  }) async {
    buildCount += 1;
    if (error != null) throw error!;

    return plan ??
        SimplePlan(
          plannedForUtc: plannedForUtc,
          budgetPhpCents: budgetPhpCents,
          originArea: origin.area,
          partySize: RetrievalRepository.partySize,
          radiusM: 5000,
          stops: const [],
          legs: const [],
          totals: const PlanTotals(
            placesPhpCents: 0,
            faresPhpCents: 0,
            totalPhpCents: 0,
            unpricedLegs: 0,
            isComplete: true,
          ),
          candidateActivities: const [],
        );
  }
}

/// Records what the screen asked the server to do, and hands back whatever the
/// test says the server would reply.
///
/// It deliberately does **not** recompute totals or reorder anything itself.
/// `edit_plan` recomputes every peso in Postgres (invariant 3), so a fake that
/// did its own arithmetic would be testing the fake — and would hide the very
/// drift the single `write_plan_stops` path exists to prevent. What these tests
/// check is which stop list the screen sends.
class FakePlansRepository implements PlansRepository {
  FakePlansRepository({this.plan, this.error});

  /// Returned by [byId] and, unchanged, by [edit].
  SavedPlan? plan;

  /// When set, [edit] throws it instead of returning.
  final Object? error;

  /// Every edit, in call order.
  ///
  /// [stops] carries the whole payload, not just the ids, because the thing
  /// most likely to be lost silently is a field nobody asserts on — the model's
  /// note and its activity pairing survive an edit only because `_stopPayload`
  /// copies them forward.
  final List<
      ({
        PlanEditType type,
        List<String> placeIds,
        List<Map<String, dynamic>> stops,
        String? target,
      })> edits = [];

  final List<Map<String, dynamic>> addedPlaces = [];

  @override
  Future<SavedPlan?> byId(String id) async => plan;

  @override
  Future<SavedPlan> edit({
    required String planId,
    required PlanEditType type,
    required List<Map<String, dynamic>> stops,
    String? targetPlaceId,
  }) async {
    edits.add((
      type: type,
      placeIds: [for (final s in stops) s['place_id'] as String],
      stops: stops,
      target: targetPlaceId,
    ));
    if (error != null) throw error!;
    return plan!;
  }

  @override
  Future<String> addUserPlace({
    required String name,
    required String category,
    required String barangay,
    required double lat,
    required double lng,
    int priceMinPhpCents = 0,
    int? priceMaxPhpCents,
  }) async {
    addedPlaces.add({
      'name': name,
      'barangay': barangay,
      'lat': lat,
      'lng': lng,
      'price_min_php_cents': priceMinPhpCents,
    });
    return 'new-place-id';
  }

  @override
  Future<List<PlanSummary>> listMine() async => const [];

  @override
  Future<String> save({
    required Map<String, dynamic> payload,
    String? title,
  }) async =>
      'saved-plan-id';
}
