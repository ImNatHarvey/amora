import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/data/retrieval_repository.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/models/resource.dart';
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

  @override
  Future<List<OriginArea>> originAreas(String city) async => areas;

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
