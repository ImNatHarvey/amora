import 'package:mobile/data/auth_repository.dart';
import 'package:mobile/data/profiles_repository.dart';
import 'package:mobile/data/resources_repository.dart';
import 'package:mobile/models/profile.dart';
import 'package:mobile/models/resource.dart';
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
